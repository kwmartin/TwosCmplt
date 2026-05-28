#!/usr/bin/env python3
"""wave_display.py – PySide6 interface for selecting and displaying circuit node waveforms.

Method 1 – circuit name on command line:
    vy wave_display.py TB_DVDR4 [--config /path/to/Config.yaml]
    Looks up TB_DVDR4.yml in circLib, TB_DVDR4.yml in specsLib, runs simulation,
    then opens the selection interface with the results.

Method 2 – no argument:
    vy wave_display.py [--config /path/to/Config.yaml]
    Opens the window immediately.  Use File > Open Circuit (Ctrl+O) to pick a circuit.
    If no spec file exists the spec editor (generateSpcs) is launched first.

Config.yaml keys used (all under fileNames:):
    simRunner      – compiled SimRun binary
    python         – Python interpreter for .py helper programs
    generateSpcs   – spec-editor script (run when no spec file is found)
    displayProgram – waveform viewer script/binary
    displayTable   – root key substituted into the viewer input file (default: waveData)
"""
from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path
from string import Template
from typing import Dict, List, Optional, Set, Tuple
import subprocess

from PySide6.QtCore import Qt, QProcess, QTimer, Signal
from PySide6.QtGui import QAction, QFont, QKeySequence, QShortcut
from PySide6.QtWidgets import (
    QApplication, QCheckBox, QDialog, QFileDialog, QFrame, QHBoxLayout,
    QLabel, QLineEdit, QMainWindow, QMessageBox, QProgressBar, QPushButton,
    QScrollArea, QSplitter, QTreeWidget, QTreeWidgetItem, QVBoxLayout, QWidget,
)

from help_viewer import MarkdownHelpWindow
from lib.glbls import rd_yml, wrt_yml, PROJECT_ROOT
from waveform_edit import WaveformCanvas as EditableCanvas
from wave_view import WaveformCanvas as ViewCanvas

getTmpltStr = lambda s, tbl: Template(s).substitute(tblNm=tbl)

CircKey = Tuple[int, ...]


# ── Data helpers ──────────────────────────────────────────────────────────────

def _merge_time_spcs(perm_ts: list, editor_ts: list) -> list:
    """Merge permanent TimeSpcs with editor-managed entries.

    Flat [name, value] entries from perm_ts whose signal name is NOT managed
    by the editor are kept at the front.  Editor {tm, vls} entries follow.
    """
    editor_names: Set[str] = set()
    for entry in editor_ts:
        if isinstance(entry, dict):
            for item in entry.get("vls", []):
                if isinstance(item, (list, tuple)) and len(item) >= 1:
                    editor_names.add(str(item[0]))
    preserved = [
        e for e in perm_ts
        if isinstance(e, (list, tuple)) and len(e) >= 1
        and str(e[0]) not in editor_names
    ]
    return preserved + list(editor_ts)


def _build_hierarchy(map_data: dict) -> Dict[CircKey, dict]:
    """Build a dict keyed by CircKey with name, module, node_names, node_nbits, children."""
    nodes: Dict[CircKey, dict] = {}
    for module, info in map_data.items():
        raw_nodes = info.get("nodes", [])
        node_names: List[str] = []
        node_nbits: List[int] = []
        for n in raw_nodes:
            if isinstance(n, dict):
                node_names.append(str(n.get("name", "")))
                node_nbits.append(int(n.get("nbits", 1)))
            else:
                node_names.append(str(n))
                node_nbits.append(1)
        for inst in info.get("instances", []):
            key: CircKey = tuple(inst["circIndxs"])
            nodes[key] = {
                "name":       inst["name"],
                "module":     module,
                "node_names": node_names,
                "node_nbits": node_nbits,
                "children":   [],
            }
    for key in nodes:
        if len(key) > 1:
            parent = key[:-1]
            if parent in nodes:
                nodes[parent]["children"].append(key)
    for entry in nodes.values():
        entry["children"].sort()
    return nodes


def _hline() -> QFrame:
    f = QFrame()
    f.setFrameShape(QFrame.Shape.HLine)
    f.setFrameShadow(QFrame.Shadow.Sunken)
    return f


def _center_on_screen(widget) -> None:
    screen = QApplication.primaryScreen().availableGeometry()
    geo = widget.frameGeometry()
    geo.moveCenter(screen.center())
    widget.move(geo.topLeft())


def _is_power_rail(name: str) -> bool:
    """True for VDD/VSS power rails that should never be auto-displayed."""
    n = name.rsplit(".", 1)[-1].lower()
    return n.startswith("vd") or n.startswith("vs")


# ── Go-to dialog ──────────────────────────────────────────────────────────────

class _GoToDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Go To Period")
        self.setFixedSize(290, 110)
        vbox = QVBoxLayout(self)
        vbox.addWidget(QLabel("Center waveform display at period:"))
        self._le = QLineEdit()
        self._le.setPlaceholderText("e.g. 10")
        self._le.returnPressed.connect(self.accept)
        vbox.addWidget(self._le)
        btn_row = QHBoxLayout()
        ok_btn = QPushButton("Accept")
        ok_btn.clicked.connect(self.accept)
        cancel_btn = QPushButton("Cancel")
        cancel_btn.clicked.connect(self.reject)
        btn_row.addWidget(ok_btn)
        btn_row.addWidget(cancel_btn)
        vbox.addLayout(btn_row)

    def period(self) -> "Optional[float]":
        try:
            return float(self._le.text())
        except ValueError:
            return None


# ── Display window ────────────────────────────────────────────────────────────

class DisplayWindow(QMainWindow):
    """Waveform display: editable inputs at top, read-only simulation outputs below."""

    simulate_clicked = Signal()
    save_clicked     = Signal()

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Waveform Display")
        self.resize(1280, 760)
        self._current_circuit: Optional[str] = None
        self._cursor_t_pu: Optional[float] = None
        self._marker_t_pu: Optional[float] = None
        self._main_win = None
        self._build_ui()
        self._build_menu()

    def _build_menu(self):
        file_menu = self.menuBar().addMenu("File")
        save_act = QAction("Save Inputs", self)
        save_act.setShortcut(QKeySequence("Ctrl+S"))
        save_act.triggered.connect(self.save_clicked)
        file_menu.addAction(save_act)
        file_menu.addSeparator()
        goto_sel_act = QAction("Goto Select", self)
        goto_sel_act.setShortcut(QKeySequence("Ctrl+H"))
        goto_sel_act.triggered.connect(self._goto_selector)
        file_menu.addAction(goto_sel_act)
        file_menu.addSeparator()
        close_act = QAction("Close", self)
        close_act.setShortcut(QKeySequence("Ctrl+W"))
        close_act.triggered.connect(self.close)
        file_menu.addAction(close_act)

        wave_menu = self.menuBar().addMenu("Wave")

        up_act = QAction("Move Up", self)
        up_act.setShortcut(QKeySequence("Ctrl+Up"))
        up_act.triggered.connect(self.viewer.move_selection_up)
        wave_menu.addAction(up_act)

        down_act = QAction("Move Down", self)
        down_act.setShortcut(QKeySequence("Ctrl+Down"))
        down_act.triggered.connect(self.viewer.move_selection_down)
        wave_menu.addAction(down_act)

        delete_act = QAction("Delete", self)
        delete_act.setShortcut(QKeySequence("Ctrl+D"))
        delete_act.triggered.connect(self.viewer.delete_selected_waves)
        wave_menu.addAction(delete_act)

        wave_menu.addSeparator()

        goto_act = QAction("Go To…", self)
        goto_act.setShortcut(QKeySequence("Ctrl+G"))
        goto_act.triggered.connect(self._goto)
        wave_menu.addAction(goto_act)

        zoom_menu = self.menuBar().addMenu("Zoom")

        full_act = QAction("Full", self)
        full_act.setShortcut(QKeySequence("Ctrl+F"))
        full_act.triggered.connect(self._zoom_full)
        zoom_menu.addAction(full_act)

        start_act = QAction("Pan to Start", self)
        start_act.setShortcuts([QKeySequence("Ctrl+0"), QKeySequence("Ctrl+B")])
        start_act.triggered.connect(self._pan_to_start)
        zoom_menu.addAction(start_act)

        markers_menu = self.menuBar().addMenu("Markers")

        drop_act = QAction("Drop Marker\tCtrl+Right-Click", self)
        drop_act.triggered.connect(self.viewer.drop_marker_at_cursor)
        markers_menu.addAction(drop_act)

        help_menu = self.menuBar().addMenu("Help")

        help_act = QAction("Help", self)
        help_act.triggered.connect(self._show_help)
        help_menu.addAction(help_act)

        about_act = QAction("About", self)
        about_act.triggered.connect(self._show_about)
        help_menu.addAction(about_act)

    def _show_help(self):
        base_dir = Path(__file__).resolve().parent
        doc_path = base_dir / "wave_display.md"
        if not hasattr(self, "_help_windows"):
            self._help_windows = []
        win = MarkdownHelpWindow(doc_path, self)
        win.show()
        win.raise_()
        win.activateWindow()
        self._help_windows.append(win)

    def _show_about(self):
        QMessageBox.about(
            self,
            "About Wave Display",
            (
                "Wave Display\n\n"
                "A PySide6 tool for selecting circuit nodes and viewing\n"
                "simulation waveforms produced by the TwosCmplt simulator.\n\n"
                "Input waveforms (top pane) are fully editable.\n"
                "Simulation output waveforms (bottom pane) are read-only.\n\n"
                "See Help → Help for full documentation."
            ),
        )

    def _goto_selector(self):
        if self._main_win is not None:
            self._main_win.show()
            self._main_win.raise_()
            self._main_win.activateWindow()

    def _goto(self):
        dlg = _GoToDialog(self)
        if dlg.exec():
            p = dlg.period()
            if p is not None:
                self._center_at(p)

    def _zoom_full(self):
        self.editor.zoom_full()
        self.viewer.zoom_full()

    def _pan_to_start(self):
        for canvas in (self.editor, self.viewer):
            canvas.left_time = 0.0
            canvas.clamp_left_time()
            canvas.update_scrollbars()
            canvas.refresh_label_layout()
            canvas.update()

    def _center_at(self, period: float):
        for canvas in (self.editor, self.viewer):
            vis = canvas.visible_time_span()
            canvas.show_range(period - vis / 2, period + vis / 2)

    def _sync_label_width(self, width: int):
        """Keep the editor label panel the same width as the viewer's dynamic label panel."""
        self.editor.label_panel_width = width
        self.editor.refresh_label_layout()
        self.editor.update()

    def _adjust_splitter(self):
        """Size the top pane to fit editor content, capped at 30% of window height."""
        total = self._vsplit.height()
        if total <= 0:
            return
        label_overhead = 24  # approx height of the "Input Waveforms" label + spacing
        canvas_h = self.editor.content_height() + self.editor.hbar.height()
        needed = label_overhead + canvas_h
        max_h = int(0.30 * self.height())
        top_h = max(60, min(needed, max_h))
        bot_h = max(0, total - top_h - self._vsplit.handleWidth())
        self._vsplit.setSizes([top_h, bot_h])

    def resizeEvent(self, event):
        super().resizeEvent(event)
        sizes = self._vsplit.sizes()
        if sizes and sizes[0] > int(0.30 * self.height()):
            self._adjust_splitter()

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        root_vbox = QVBoxLayout(central)
        root_vbox.setContentsMargins(4, 4, 4, 4)
        root_vbox.setSpacing(4)

        vsplit = QSplitter(Qt.Orientation.Vertical)

        top = QWidget()
        tv = QVBoxLayout(top)
        tv.setContentsMargins(0, 0, 0, 0)
        tv.setSpacing(2)
        top_lbl = QLabel("Input Waveforms (editable)")
        top_lbl.setFont(QFont("monospace", 9))
        tv.addWidget(top_lbl)
        self.editor = EditableCanvas()
        tv.addWidget(self.editor, stretch=1)
        vsplit.addWidget(top)

        bot = QWidget()
        bv = QVBoxLayout(bot)
        bv.setContentsMargins(0, 0, 0, 0)
        bv.setSpacing(2)
        bot_lbl = QLabel("Output Waveforms")
        bot_lbl.setFont(QFont("monospace", 9))
        bv.addWidget(bot_lbl)
        self.viewer = ViewCanvas()
        bv.addWidget(self.viewer, stretch=1)
        vsplit.addWidget(bot)

        self.editor.view_changed.connect(self.viewer.apply_view)
        self.viewer.view_changed.connect(self.editor.apply_view)
        self.viewer.label_width_changed.connect(self._sync_label_width)
        self.editor.cursor_moved_pu.connect(self._on_cursor_pu)
        self.viewer.cursor_moved_pu.connect(self._on_cursor_pu)
        self.viewer.marker_changed.connect(self._on_marker_changed)

        vsplit.setStretchFactor(0, 0)  # top pane: fixed size
        vsplit.setStretchFactor(1, 1)  # bottom pane: absorbs resize
        vsplit.setSizes([240, 480])
        self._vsplit = vsplit
        root_vbox.addWidget(vsplit, stretch=1)

        btn_row = QHBoxLayout()
        for label, tip, sig in [
            ("Simulate",    "Run simulation with current input waveforms", self.simulate_clicked),
            ("Save Inputs", "Save edited input waveforms to the spec file", self.save_clicked),
        ]:
            b = QPushButton(label)
            b.setToolTip(tip)
            b.clicked.connect(sig)
            btn_row.addWidget(b)
        self._pos_label = QLabel()
        self._pos_label.setFont(QFont("monospace", 9))
        self._pos_label.setStyleSheet("color: #60a5fa; padding-left: 12px;")
        btn_row.addWidget(self._pos_label)
        btn_row.addStretch()
        root_vbox.addLayout(btn_row)

    def load_spec(self, spec_path: Path, circuit_name: str):
        """Load spec into the editable inputs canvas; no-op if circuit unchanged."""
        if self._current_circuit == circuit_name:
            return
        self._current_circuit = circuit_name
        try:
            self.editor.load_base_yaml(spec_path)
            # Drop power rails (VDD, VSS) — they never change, no point showing them
            self.editor._preserved_nonclock_waves = [
                w for w in self.editor._preserved_nonclock_waves
                if not _is_power_rail(w.label_text)
            ]
            self.editor.rebuild_waves_from_specs()
            self.editor.refresh_label_layout()
            self.editor.update()
            QTimer.singleShot(0, self._adjust_splitter)
        except Exception:
            pass

    def load_outputs(self, signals: dict):
        """Replace output waveforms, preserving any user-defined display order."""
        saved_order = [w.label_text for w in self.viewer.waves]
        self.viewer.load_signals(signals)
        if saved_order:
            by_label = {w.label_text: w for w in self.viewer.waves}
            reordered = [by_label.pop(lbl) for lbl in saved_order if lbl in by_label]
            reordered.extend(by_label.values())  # new signals appended at end
            if reordered:
                self.viewer.waves = reordered
                self.viewer._rebuild_label_widgets()
                self.viewer.refresh_label_layout()
                self.viewer.update()

    def _on_cursor_pu(self, t_pu):
        self._cursor_t_pu = t_pu
        self._update_pos_label()

    def _on_marker_changed(self, t_pu):
        self._marker_t_pu = t_pu
        self._update_pos_label()

    def _update_pos_label(self):
        c = self._cursor_t_pu
        m = self._marker_t_pu
        if m is not None and c is not None:
            delta = c - m
            self._pos_label.setText(
                f"Marker: {m:.2f}    Pos: {c:.2f}    Δ: {delta:+.2f} per"
            )
        elif m is not None:
            self._pos_label.setText(f"Marker: {m:.2f}")
        elif c is not None:
            self._pos_label.setText(f"Pos: {c:.2f}")
        else:
            self._pos_label.setText("")

    def get_editor_yaml(self) -> dict:
        return self.editor.build_yaml_dict()

    def apply_viewer_order(self, names: List[str]):
        """Reorder viewer waves to match a saved name list (best-effort)."""
        by_label = {w.label_text: w for w in self.viewer.waves}
        reordered = [by_label.pop(n) for n in names if n in by_label]
        reordered.extend(by_label.values())
        if reordered:
            self.viewer.waves = reordered
            self.viewer._rebuild_label_widgets()
            self.viewer.refresh_label_layout()
            self.viewer.update()

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_A and (event.modifiers() & Qt.ControlModifier):
            main = getattr(self, "_main_win", None)
            if main is not None:
                main.activateWindow()
                main.raise_()
            event.accept()
            return
        super().keyPressEvent(event)

    def closeEvent(self, event):
        main = getattr(self, "_main_win", None)
        if main is not None:
            main._save_wave_state()
        super().closeEvent(event)


# ── Main window ───────────────────────────────────────────────────────────────

class WaveDisplay(QMainWindow):
    def __init__(self, config_path: str, circuit_name: Optional[str] = None):
        super().__init__()
        self.setWindowTitle("Wave Display")

        self._cfg: dict                          = rd_yml(config_path) or {}
        self._config_path: str                   = str(Path(config_path).resolve())
        self._chngs: list                        = []
        self._map: dict                          = {}
        self._hierarchy: Dict[CircKey, dict]     = {}
        self._selection: Dict[CircKey, Set[int]] = {}
        self._signal_order: List[Tuple[CircKey, int]] = []  # ordered list of selected signals
        self._current_key: Optional[CircKey]     = None
        self._node_cbs: List[QCheckBox]          = []
        self._circuit_name: Optional[str]            = None
        self._display_win: Optional[DisplayWindow]   = None
        self._temp_spec_path: Optional[str]          = None

        self._build_new: bool = bool(self._cfg.get("buildNew", True))

        self._build_ui()

        if circuit_name:
            if self._build_new:
                QTimer.singleShot(0, lambda: self._rebuild(circuit_name))
            else:
                QTimer.singleShot(0, lambda: self._load_circuit(circuit_name))

    # ── Help ──────────────────────────────────────────────────────────────────

    def _show_help(self):
        base_dir = Path(__file__).resolve().parent
        doc_path = base_dir / "wave_display.md"
        if not hasattr(self, "_help_windows"):
            self._help_windows = []
        win = MarkdownHelpWindow(doc_path, self)
        win.show()
        win.raise_()
        win.activateWindow()
        self._help_windows.append(win)

    def _show_about(self):
        QMessageBox.about(
            self,
            "About Wave Display",
            (
                "Wave Display\n\n"
                "A PySide6 tool for selecting circuit nodes and viewing\n"
                "simulation waveforms produced by the TwosCmplt simulator.\n\n"
                "Navigate the circuit hierarchy, select nodes to display,\n"
                "and run simulations from this window.\n\n"
                "See Help → Help for full documentation."
            ),
        )

    # ── UI construction ───────────────────────────────────────────────────────

    def _build_ui(self):
        # Menu bar
        file_menu = self.menuBar().addMenu("File")
        open_act  = QAction("Open Circuit", self)
        open_act.setShortcut(QKeySequence("Ctrl+O"))
        open_act.triggered.connect(self._open_circuit_dialog)
        file_menu.addAction(open_act)
        reload_act = QAction("Reload", self)
        reload_act.setShortcut(QKeySequence("Ctrl+R"))
        reload_act.triggered.connect(self._reload)
        file_menu.addAction(reload_act)
        file_menu.addSeparator()
        quit_act  = QAction("Quit", self)
        quit_act.setShortcut(QKeySequence("Ctrl+Q"))
        quit_act.triggered.connect(self.close)
        file_menu.addAction(quit_act)

        help_menu = self.menuBar().addMenu("Help")
        help_act  = QAction("Help", self)
        help_act.triggered.connect(self._show_help)
        help_menu.addAction(help_act)
        about_act = QAction("About", self)
        about_act.triggered.connect(self._show_about)
        help_menu.addAction(about_act)

        # Status bar with indeterminate progress indicator on the right
        self._progress = QProgressBar()
        self._progress.setRange(0, 0)
        self._progress.setMaximumWidth(140)
        self._progress.setTextVisible(False)
        self._progress.setVisible(False)
        self.statusBar().addPermanentWidget(self._progress)
        self.statusBar().showMessage("Open a circuit to begin  (File > Open Circuit or Ctrl+O)")

        # Central widget
        root = QWidget()
        self.setCentralWidget(root)
        vbox = QVBoxLayout(root)
        vbox.setContentsMargins(8, 8, 8, 8)
        vbox.setSpacing(6)

        # Header: dot-separated path left, [Module] right
        hdr = QHBoxLayout()
        self._path_lbl = QLabel()
        self._path_lbl.setFont(QFont("monospace", 10))
        self._mod_lbl  = QLabel()
        self._mod_lbl.setFont(QFont("monospace", 10, QFont.Weight.Bold))
        self._mod_lbl.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        hdr.addWidget(self._path_lbl, stretch=3)
        hdr.addWidget(self._mod_lbl,  stretch=1)
        vbox.addLayout(hdr)
        vbox.addWidget(_hline())

        # Horizontal splitter: tree | node panel
        splitter = QSplitter(Qt.Orientation.Horizontal)
        vbox.addWidget(splitter, stretch=1)

        # Left: circuit hierarchy tree
        self._tree = QTreeWidget()
        self._tree.setHeaderLabel("Circuit Hierarchy")
        self._tree.currentItemChanged.connect(self._on_tree_select)
        splitter.addWidget(self._tree)

        # Right: scrollable node checkbox list + Select All / Clear
        right  = QWidget()
        rvbox  = QVBoxLayout(right)
        rvbox.setContentsMargins(4, 0, 0, 0)
        rvbox.setSpacing(4)

        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        self._node_container = QWidget()
        self._node_vbox = QVBoxLayout(self._node_container)
        self._node_vbox.setAlignment(Qt.AlignmentFlag.AlignTop)
        self._node_vbox.setSpacing(2)
        scroll.setWidget(self._node_container)
        rvbox.addWidget(scroll, stretch=1)

        node_btn_row = QHBoxLayout()
        for label, slot in [("Select All", self._select_all), ("Clear", self._clear_nodes)]:
            b = QPushButton(label)
            b.clicked.connect(slot)
            node_btn_row.addWidget(b)
        node_btn_row.addStretch()
        rvbox.addLayout(node_btn_row)

        splitter.addWidget(right)
        splitter.setSizes([260, 340])

        # Bottom action bar
        vbox.addWidget(_hline())
        action_row = QHBoxLayout()
        for label, tip, slot in [
            ("Simulate",   "Run simulation using current input waveforms (spec file unchanged)",  self._simulate),
            ("Save",       "Save node selection and input waveforms to the spec file",            self._save_spec),
            ("Display",    "Open waveform display window with current signals",                   self._display),
            ("Add",        "Add checked nodes to the saved selection and update display",         self._add),
            ("Remove",     "Remove checked nodes from the saved selection and update display",    self._remove),
            ("Remove All", "Clear the saved selection for the current circuit and update display", self._remove_all),
        ]:
            b = QPushButton(label)
            b.setToolTip(tip)
            b.clicked.connect(slot)
            action_row.addWidget(b)
        vbox.addLayout(action_row)

        self.resize(720, 560)

    # ── Circuit loading flow ──────────────────────────────────────────────────

    def _open_circuit_dialog(self):
        circ_lib = self._cfg.get("directories", {}).get("circLib", "")
        path, _  = QFileDialog.getOpenFileName(
            self, "Open Circuit", circ_lib, "YAML files (*.yml *.yaml)"
        )
        if path:
            name = Path(path).stem
            if self._build_new:
                self._rebuild(name)
            else:
                self._load_circuit(name)

    def _reload(self):
        if not self._circuit_name:
            self.statusBar().showMessage("No circuit loaded — use File > Open Circuit first")
            return
        self._rebuild(self._circuit_name)

    def closeEvent(self, event):
        self._save_wave_state()
        if self._display_win is not None:
            self._display_win.close()
        super().closeEvent(event)

    def _rebuild(self, circuit_name: str):
        runner = self._cfg.get("fileNames", {}).get("simRunner", "")
        if not runner:
            self.statusBar().showMessage("fileNames.simRunner not configured in Config.yaml")
            return
        self._progress.setVisible(True)
        self.statusBar().showMessage(f"Building {circuit_name}…")
        self._circuit_name = circuit_name
        self.setWindowTitle(f"Wave Display — {circuit_name}")
        self._rebuild_proc = QProcess(self)
        self._rebuild_proc.finished.connect(
            lambda code, _status: self._on_rebuild_done(circuit_name, code)
        )
        self._rebuild_proc.start(runner, [circuit_name, self._config_path, "--rebuild"])

    def _on_rebuild_done(self, circuit_name: str, exit_code: int):
        self._progress.setVisible(False)
        if exit_code != 0:
            self.statusBar().showMessage(
                f"Rebuild failed for {circuit_name} (exit {exit_code})"
            )
            return
        self._load_circuit(circuit_name)

    def _load_circuit(self, circuit_name: str):
        self._circuit_name = circuit_name
        self.setWindowTitle(f"Wave Display — {circuit_name}")

        dump_dir   = Path(self._cfg.get("directories", {}).get("dumpDir", ""))
        map_path   = dump_dir / f"{circuit_name}Map.yml"
        chngs_path = dump_dir / f"{circuit_name}Chngs.yml"

        if map_path.exists():
            self._map       = rd_yml(str(map_path)) or {}
            self._chngs     = rd_yml(str(chngs_path)) or [] if chngs_path.exists() else []
            self._hierarchy = _build_hierarchy(self._map)
            self._selection.clear()
            self._current_key = None
            self._node_cbs.clear()
            self._populate_tree()
            self.statusBar().showMessage(
                f"Ready — {circuit_name}  (click Simulate to re-run)"
            )
        else:
            self.statusBar().showMessage(
                f"Circuit: {circuit_name} — click Simulate to run"
            )

    def _simulate(self):
        if not self._circuit_name:
            self.statusBar().showMessage("No circuit loaded — use File > Open Circuit first")
            return
        self._save()
        specs_lib = Path(self._cfg.get("directories", {}).get("specsLib", ""))
        spec_file = specs_lib / f"{self._circuit_name}.yml"
        if not spec_file.exists():
            self.statusBar().showMessage(
                f"No spec file for {self._circuit_name} — cannot simulate"
            )
            return

        # Use editor state from display window to build a temp spec; spec file is unchanged.
        tmp_path: Optional[str] = None
        if self._display_win is not None:
            try:
                # Start from full permanent spec so all required fields are present.
                canvas_data = rd_yml(str(spec_file)) or {}
                editor_data = self._display_win.get_editor_yaml()
                perm_ts = canvas_data.get("TimeSpcs", [])
                editor_ts = editor_data.get("TimeSpcs", [])
                for k, v in editor_data.items():
                    if k != "TimeSpcs":
                        canvas_data[k] = v
                canvas_data["TimeSpcs"] = _merge_time_spcs(perm_ts, editor_ts)
                save_nds = self._build_save_nds()
                perm_save_nds = canvas_data.get("SaveNds", [])
                # Always include permanent SaveNds so the simulator outputs them too.
                dynamic_names: Set[str] = {
                    nd.get("name", "") if isinstance(nd, dict) else str(nd)
                    for nd in save_nds
                }
                merged = list(save_nds) + [
                    nd for nd in perm_save_nds
                    if (nd.get("name", "") if isinstance(nd, dict) else str(nd))
                    not in dynamic_names
                ]
                canvas_data["SaveNds"] = merged if merged else perm_save_nds
                fd, tmp_path = tempfile.mkstemp(suffix=".yml", prefix="wd_spec_")
                os.close(fd)
                wrt_yml(tmp_path, canvas_data)
            except Exception as exc:
                msg = f"Failed to build temp spec: {exc}"
                self.statusBar().showMessage(msg)
                self._display_win.statusBar().showMessage(msg)
                return

        self._start_sim(self._circuit_name, spec_path=tmp_path)

    def _update_save_nds(self, spec_file: Path):
        spec = rd_yml(str(spec_file)) or {}
        save_nds = []
        for key, indices in self._selection.items():
            node_names = self._hierarchy.get(key, {}).get("node_names", [])
            path_str   = ".".join(self._path_parts(key))
            for idx in sorted(indices):
                if idx < len(node_names):
                    save_nds.append({"name": path_str + "." + node_names[idx], "format": "u"})
        spec["SaveNds"] = save_nds
        wrt_yml(str(spec_file), spec)

    # ── Simulation ────────────────────────────────────────────────────────────

    def _start_sim(self, circuit_name: str, spec_path: Optional[str] = None):
        runner = self._cfg.get("fileNames", {}).get("simRunner", "")
        if not runner:
            self.statusBar().showMessage("fileNames.simRunner not configured in Config.yaml")
            return

        self._progress.setVisible(True)
        self.statusBar().showMessage(f"Simulating {circuit_name}…")
        if self._display_win is not None:
            self._display_win.statusBar().showMessage(f"Simulating {circuit_name}…")
        self._temp_spec_path = spec_path

        args = [circuit_name, self._config_path]
        if spec_path:
            args += ["--spec", spec_path]

        self._sim_proc = QProcess(self)
        self._sim_proc.finished.connect(
            lambda code, _status: self._on_sim_done(circuit_name, code)
        )
        self._sim_proc.start(runner, args)

    def _on_sim_done(self, circuit_name: str, exit_code: int):
        self._progress.setVisible(False)

        # Clean up temporary spec file used for this simulation run.
        if self._temp_spec_path:
            try:
                os.unlink(self._temp_spec_path)
            except OSError:
                pass
            self._temp_spec_path = None

        if exit_code != 0:
            msg = f"Simulation failed for {circuit_name} (exit {exit_code})"
            self.statusBar().showMessage(msg)
            if self._display_win is not None:
                self._display_win.statusBar().showMessage(msg)
            return

        dump_dir   = Path(self._cfg.get("directories", {}).get("dumpDir", ""))
        chngs_path = str(dump_dir / f"{circuit_name}Chngs.yml")
        map_path   = str(dump_dir / f"{circuit_name}Map.yml")

        self._chngs     = rd_yml(chngs_path) or []
        self._map       = rd_yml(map_path)   or {}
        self._hierarchy = _build_hierarchy(self._map)

        # Drop selections whose circuit keys no longer exist in the new hierarchy
        valid_keys = set(self._hierarchy.keys())
        self._selection = {k: v for k, v in self._selection.items() if k in valid_keys}
        self._signal_order = [(k, i) for k, i in self._signal_order if k in valid_keys]
        self._current_key = None
        self._node_cbs.clear()
        self._populate_tree()
        self.statusBar().showMessage(f"Ready — {circuit_name}")
        if self._display_win is not None:
            self._display_win.statusBar().showMessage(f"Ready — {circuit_name}")

        self._display()

    def _write_output_waves(self, circuit_name: str) -> "Optional[Path]":
        signals = self._collect_signals()
        if not signals:
            return None
        dump_dir = Path(self._cfg.get("directories", {}).get("dumpDir", "/tmp/"))
        out_path = dump_dir / f"{circuit_name}_out_waves.yml"
        lines = ["waves:"]
        for sig_name, data in signals.items():
            lines.append(f"- name: {sig_name}")
            lines.append(f"  nbits: {data['nbits']}")
            lines.append(f"  changes:")
            for t, v in data["changes"]:
                lines.append(f"  - [{t}, {v}]")
        out_path.write_text("\n".join(lines) + "\n")
        return out_path

    def _launch_wave_editor(self, circuit_name: str, output_path: "Optional[Path]"):
        fn        = self._cfg.get("fileNames", {})
        python    = fn.get("python", sys.executable)
        gen_specs = fn.get("generateSpcs", "")
        if not gen_specs:
            return
        args = [python, gen_specs, circuit_name]
        if output_path is not None:
            args.append(str(output_path))
        subprocess.Popen(args)

    def _build_save_nds(self) -> list:
        """Return a SaveNds list from the current selection in click order."""
        save_nds = []
        seen: Set[str] = set()
        for key, idx in self._signal_order:
            node_names = self._hierarchy.get(key, {}).get("node_names", [])
            path_str   = ".".join(self._path_parts(key))
            if idx < len(node_names):
                name = path_str + "." + node_names[idx]
                if name not in seen:
                    save_nds.append({"name": name, "format": "u"})
                    seen.add(name)
        return save_nds

    def _save_spec(self):
        """Save edited input waveforms and node selection permanently to the spec file."""
        self._save()
        if not self._circuit_name:
            return
        specs_lib = Path(self._cfg.get("directories", {}).get("specsLib", ""))
        spec_file = specs_lib / f"{self._circuit_name}.yml"
        if not spec_file.exists():
            self.statusBar().showMessage(
                f"No spec file for {self._circuit_name} — nothing to save"
            )
            return

        # Start from the full existing spec to preserve fields the editor doesn't manage.
        spec_data = rd_yml(str(spec_file)) or {}
        if self._display_win is not None:
            try:
                editor_data = self._display_win.get_editor_yaml()
                perm_ts = spec_data.get("TimeSpcs", [])
                editor_ts = editor_data.get("TimeSpcs", [])
                for k, v in editor_data.items():
                    if k != "TimeSpcs":
                        spec_data[k] = v
                spec_data["TimeSpcs"] = _merge_time_spcs(perm_ts, editor_ts)
            except Exception as exc:
                self.statusBar().showMessage(f"Failed to read editor state: {exc}")
                return

        save_nds = self._build_save_nds()
        if not save_nds:
            save_nds = spec_data.get("SaveNds", [])
        spec_data["SaveNds"] = save_nds
        wrt_yml(str(spec_file), spec_data)
        self.statusBar().showMessage(f"Saved spec for {self._circuit_name}")

    # ── Tree ─────────────────────────────────────────────────────────────────

    def _populate_tree(self):
        self._tree.clear()
        self._tree_map: Dict[CircKey, QTreeWidgetItem] = {}
        if not self._hierarchy:
            return
        root_key  = min(self._hierarchy, key=lambda k: len(k))
        root_item = self._make_item(root_key)
        self._tree.addTopLevelItem(root_item)
        self._tree_map[root_key] = root_item
        self._add_children(root_item, root_key)
        root_item.setExpanded(True)   # show direct children; deeper levels collapsed

    def _make_item(self, key: CircKey) -> QTreeWidgetItem:
        item = QTreeWidgetItem([self._hierarchy[key]["name"]])
        item.setData(0, Qt.ItemDataRole.UserRole, key)
        return item

    def _add_children(self, parent: QTreeWidgetItem, key: CircKey):
        for child_key in self._hierarchy[key]["children"]:
            item = self._make_item(child_key)
            parent.addChild(item)
            self._tree_map[child_key] = item
            self._add_children(item, child_key)

    def _on_tree_select(self, current: QTreeWidgetItem, _prev):
        if self._current_key is not None:
            self._save()  # persist checkboxes before switching to another circuit
        if current is None:
            return
        key: CircKey = current.data(0, Qt.ItemDataRole.UserRole)
        if key is None:
            return
        self._current_key = key
        info = self._hierarchy[key]
        self._path_lbl.setText(".".join(self._path_parts(key)))
        self._mod_lbl.setText(f"[{info['module']}]")
        self._populate_nodes(key)

    def _path_parts(self, key: CircKey) -> List[str]:
        parts: List[str] = []
        k = key
        while k in self._hierarchy:
            parts.append(self._hierarchy[k]["name"])
            if len(k) <= 1:
                break
            k = k[:-1]
        parts.reverse()
        return parts

    # ── Node panel ────────────────────────────────────────────────────────────

    def _populate_nodes(self, key: CircKey):
        while self._node_vbox.count():
            item = self._node_vbox.takeAt(0)
            w = item.widget()
            if w:
                w.deleteLater()
        self._node_cbs.clear()

        saved = self._selection.get(key, set())
        for i, name in enumerate(self._hierarchy[key]["node_names"]):
            cb = QCheckBox(name)
            cb.blockSignals(True)
            cb.setChecked(i in saved)
            cb.blockSignals(False)
            cb.stateChanged.connect(lambda state, n=i: self._on_cb_state_changed(n, state))
            self._node_vbox.addWidget(cb)
            self._node_cbs.append(cb)

    def _on_cb_state_changed(self, idx: int, state: int):
        key = self._current_key
        if key is None:
            return
        entry = (key, idx)
        if state:  # Qt.Checked == 2, Unchecked == 0
            if entry not in self._signal_order:
                self._signal_order.append(entry)
        else:
            try:
                self._signal_order.remove(entry)
            except ValueError:
                pass

    def _checked_indices(self) -> Set[int]:
        return {i for i, cb in enumerate(self._node_cbs) if cb.isChecked()}

    def _select_all(self):
        if self._current_key is None:
            return
        node_names = self._hierarchy[self._current_key]["node_names"]
        for i, cb in enumerate(self._node_cbs):
            if not _is_power_rail(node_names[i]):
                cb.setChecked(True)

    def _clear_nodes(self):
        for cb in self._node_cbs:
            cb.setChecked(False)

    # ── Selection actions ─────────────────────────────────────────────────────

    def _save(self):
        if self._current_key is None:
            return
        # _signal_order is maintained in real-time via _on_cb_state_changed; just sync _selection.
        checked = self._checked_indices()
        if checked:
            self._selection[self._current_key] = checked
        else:
            self._selection.pop(self._current_key, None)

    def _add(self):
        if self._current_key is not None:
            self._selection.setdefault(self._current_key, set()).update(self._checked_indices())
            # _signal_order already updated in real-time via _on_cb_state_changed
            self._populate_nodes(self._current_key)
        self._display()

    def _remove(self):
        if self._current_key is not None:
            to_rm = self._checked_indices() & self._selection.get(self._current_key, set())
            remaining = self._selection.get(self._current_key, set()) - to_rm
            if remaining:
                self._selection[self._current_key] = remaining
            else:
                self._selection.pop(self._current_key, None)
            for idx in sorted(to_rm):
                try:
                    self._signal_order.remove((self._current_key, idx))
                except ValueError:
                    pass
            self._populate_nodes(self._current_key)
        self._display()

    def _remove_all(self):
        if self._current_key is not None:
            for idx in list(self._selection.get(self._current_key, set())):
                try:
                    self._signal_order.remove((self._current_key, idx))
                except ValueError:
                    pass
            self._selection.pop(self._current_key, None)
            self._populate_nodes(self._current_key)
        self._display()

    def _on_waves_deleted(self, deleted_labels: list):
        """Called when viewer waves are deleted; delegates to sync helper."""
        self._sync_selection_to_viewer()

    def _sync_selection_to_viewer(self):
        """Remove from _selection/_signal_order any entries whose wave is absent from the viewer.

        Call this whenever the viewer's wave list changes (signals added or removed).
        """
        if self._display_win is None:
            return
        viewer_labels = {w.label_text for w in self._display_win.viewer.waves}

        # Find _signal_order entries with no matching wave in the viewer
        to_remove = []
        for key, idx in list(self._signal_order):
            node_names = self._hierarchy.get(key, {}).get("node_names", [])
            if idx < len(node_names):
                path_str = ".".join(self._path_parts(key))
                label = path_str + "." + node_names[idx]
                if label not in viewer_labels:
                    to_remove.append((key, idx))

        if not to_remove:
            return

        affected_keys: set = set()
        for entry in to_remove:
            key, idx = entry
            try:
                self._signal_order.remove(entry)
            except ValueError:
                pass
            if key in self._selection:
                self._selection[key].discard(idx)
                if not self._selection[key]:
                    self._selection.pop(key)
            affected_keys.add(key)

        if self._current_key in affected_keys:
            saved = self._selection.get(self._current_key, set())
            for i, cb in enumerate(self._node_cbs):
                cb.blockSignals(True)
                cb.setChecked(i in saved)
                cb.blockSignals(False)

    # ── Display state persistence ─────────────────────────────────────────────

    def _state_path(self) -> "Optional[Path]":
        if not self._circuit_name:
            return None
        dump_dir = Path(self._cfg.get("directories", {}).get("dumpDir", ""))
        return dump_dir / f"{self._circuit_name}_wave_state.yml"

    def _save_wave_state(self, viewer_waves: "Optional[list]" = None):
        path = self._state_path()
        if path is None:
            return
        waves = viewer_waves if viewer_waves is not None else (
            [w.label_text for w in self._display_win.viewer.waves]
            if self._display_win is not None else []
        )
        wrt_yml(str(path), {"viewer_order": waves})

    def _load_wave_state(self) -> "Optional[List[str]]":
        path = self._state_path()
        if path is None or not path.exists():
            return None
        data = rd_yml(str(path))
        if isinstance(data, dict):
            order = data.get("viewer_order")
            if isinstance(order, list):
                return [str(n) for n in order]
        return None

    # ── Display ───────────────────────────────────────────────────────────────

    def _display(self):
        self._save()

        # Refresh simulation data from disk
        if self._circuit_name:
            dump_dir   = Path(self._cfg.get("directories", {}).get("dumpDir", ""))
            chngs_path = dump_dir / f"{self._circuit_name}Chngs.yml"
            if chngs_path.exists():
                fresh = rd_yml(str(chngs_path))
                if fresh is not None:
                    self._chngs = fresh

        signals = self._collect_all_signals()

        # Normalize raw tick times to period units
        per = self._get_per()
        if per > 1.0:
            signals = {
                name: {
                    "nbits": d["nbits"],
                    "changes": [[t / per, v] for t, v in d["changes"]],
                }
                for name, d in signals.items()
            }

        # Create display window once; reuse (show) it on subsequent calls
        first_display = self._display_win is None
        if first_display:
            self._display_win = DisplayWindow()
            self._display_win._main_win = self
            self._display_win.simulate_clicked.connect(self._simulate)
            self._display_win.save_clicked.connect(self._save_spec)
            self._display_win.viewer.waves_deleted.connect(self._on_waves_deleted)
        self._display_win.show()
        if first_display:
            _center_on_screen(self._display_win)

        # Load spec into editable inputs (skipped if circuit hasn't changed)
        if self._circuit_name:
            specs_lib = Path(self._cfg.get("directories", {}).get("specsLib", ""))
            spec_file = specs_lib / f"{self._circuit_name}.yml"
            if spec_file.exists():
                self._display_win.load_spec(spec_file, self._circuit_name)
            self._display_win.setWindowTitle(f"Waveform Display — {self._circuit_name}")

        if signals:
            self._display_win.load_outputs(signals)
            # On the very first display, restore saved viewer order only when there
            # is no live click order — if the user has selected nodes, _collect_all_signals
            # already returned them in click order so apply_viewer_order would override it.
            if first_display and not self._signal_order:
                saved = self._load_wave_state()
                if saved:
                    self._display_win.apply_viewer_order(saved)
            self._sync_selection_to_viewer()

        # Persist current viewer order
        self._save_wave_state()

        self._display_win.raise_()
        if not signals:
            self.statusBar().showMessage(
                "No signals to display — run Simulate first or select nodes"
            )

    def _get_per(self) -> float:
        """Return PER constant from the current circuit's spec file, or 1.0 if not found."""
        if not self._circuit_name:
            return 1.0
        specs_lib = Path(self._cfg.get("directories", {}).get("specsLib", ""))
        spec_file = specs_lib / f"{self._circuit_name}.yml"
        if not spec_file.exists():
            return 1.0
        spec = rd_yml(str(spec_file)) or {}
        constants = spec.get("Constants")
        if isinstance(constants, dict):
            try:
                return float(constants["PER"])
            except (KeyError, TypeError, ValueError):
                return 1.0
        if isinstance(constants, list):
            for item in constants:
                if isinstance(item, (list, tuple)) and len(item) == 2 and str(item[0]) == "PER":
                    try:
                        return float(item[1])
                    except (TypeError, ValueError):
                        pass
        return 1.0

    def _collect_all_signals(self) -> Dict[str, dict]:
        """Collect signals in display order: Clock → TimeSpcs → SaveNds → selected nodes.

        All waveform data is taken from self._chngs (Glbls.nodeChngs output).
        Signals in the spec file are resolved via the circuit hierarchy map.
        Checkbox-selected signals are appended if not already included.
        """
        if not self._circuit_name or not self._hierarchy or not self._chngs:
            return self._collect_signals()

        specs_lib = Path(self._cfg.get("directories", {}).get("specsLib", ""))
        spec_file = specs_lib / f"{self._circuit_name}.yml"
        if not spec_file.exists():
            return self._collect_signals()

        spec = rd_yml(str(spec_file)) or {}

        # Build a fast index: (circIndxs_tuple, nodeIndx) → {nbits, changes}
        chngs_index: Dict[tuple, dict] = {}
        for chng in self._chngs:
            k = (tuple(chng["circIndxs"]), chng["nodeIndx"])
            if k not in chngs_index:
                chngs_index[k] = {"nbits": chng.get("nbits", 1), "changes": []}
            chngs_index[k]["changes"].append([chng["updTm"], chng["value"]])

        root_key  = min(self._hierarchy, key=lambda k: len(k))
        root_name = self._hierarchy[root_key]["name"]
        root_nodes: List[str] = self._hierarchy[root_key]["node_names"]

        def _short(name: str) -> Optional[Tuple[CircKey, int]]:
            if name in root_nodes:
                return (root_key, root_nodes.index(name))
            return None

        def _path(full_name: str) -> Optional[Tuple[CircKey, int]]:
            parts = full_name.split(".")
            if parts and parts[0] == root_name:
                parts = parts[1:]
            if not parts:
                return None
            current = root_key
            while len(parts) > 1:
                for child_key in self._hierarchy[current]["children"]:
                    if self._hierarchy[child_key]["name"] == parts[0]:
                        current = child_key
                        parts = parts[1:]
                        break
                else:
                    return None
            node_names = self._hierarchy[current]["node_names"]
            if parts[0] in node_names:
                return (current, node_names.index(parts[0]))
            return None

        ordered: List[str] = []
        name_to_ck: Dict[str, Tuple[CircKey, int]] = {}
        seen: Set[str] = set()

        def _add(display_name: str, key: CircKey, idx: int):
            if display_name not in seen and not _is_power_rail(display_name):
                ordered.append(display_name)
                name_to_ck[display_name] = (key, idx)
                seen.add(display_name)

        # 1. Clock signals
        clk_names: Set[str] = set()
        for clk in spec.get("Clock", []):
            if isinstance(clk, dict):
                nm = str(clk.get("clkNm", "CLK"))
                clk_names.add(nm)
                r = _short(nm)
                if r:
                    _add(root_name + "." + nm, r[0], r[1])

        # 2. TimeSpcs input signals (excluding clocks) — both flat and dict entries
        ts_seen: Set[str] = set()
        for entry in spec.get("TimeSpcs", []):
            if isinstance(entry, (list, tuple)) and len(entry) >= 1:
                # flat [name, value] initial-value entry
                nm = str(entry[0])
                if nm not in clk_names and nm not in ts_seen:
                    ts_seen.add(nm)
                    r = _short(nm)
                    if r:
                        _add(root_name + "." + nm, r[0], r[1])
                continue
            if not isinstance(entry, dict):
                continue
            for item in entry.get("vls", []):
                if isinstance(item, (list, tuple)) and len(item) >= 2:
                    nm = str(item[0])
                    if nm in clk_names or nm in ts_seen:
                        continue
                    ts_seen.add(nm)
                    r = _short(nm)
                    if r:
                        _add(root_name + "." + nm, r[0], r[1])

        # 3. SaveNds signals
        for nd in spec.get("SaveNds", []):
            full_name = nd.get("name", "") if isinstance(nd, dict) else str(nd)
            if not full_name:
                continue
            r = _path(full_name)
            if r:
                _add(full_name, r[0], r[1])

        # 4. Checkbox-selected signals in click order
        for key, idx in self._signal_order:
            node_names = self._hierarchy.get(key, {}).get("node_names", [])
            path_str   = ".".join(self._path_parts(key))
            if idx < len(node_names):
                _add(path_str + "." + node_names[idx], key, idx)

        # Build final dict in display order, pulling data from chngs_index.
        # Signals with no recorded changes (e.g. stuck outputs) appear as flat zero,
        # using the nbits from the hierarchy map so multi-bit values display correctly.
        signals: Dict[str, dict] = {}
        for name in ordered:
            key, idx = name_to_ck[name]
            ck = (key, idx)
            if ck in chngs_index:
                signals[name] = chngs_index[ck]
            else:
                node_nbits = self._hierarchy.get(key, {}).get("node_nbits", [])
                nbits = node_nbits[idx] if idx < len(node_nbits) else 1
                signals[name] = {"nbits": nbits, "changes": [[0, 0]]}

        return signals

    def _collect_signals(self) -> Dict[str, dict]:
        signals: Dict[str, dict] = {}
        for chng in self._chngs:
            key: CircKey = tuple(chng["circIndxs"])
            idx: int     = chng["nodeIndx"]
            if key not in self._selection or idx not in self._selection[key]:
                continue
            info       = self._hierarchy.get(key, {})
            node_names = info.get("node_names", [])
            node_name  = node_names[idx] if idx < len(node_names) else str(idx)
            sig_name   = ".".join(self._path_parts(key)) + "." + node_name
            entry      = signals.setdefault(sig_name, {"nbits": chng["nbits"], "changes": []})
            entry["changes"].append([chng["updTm"], chng["value"]])
        return signals

    def _make_input(self, signals: Dict[str, dict], table_name: str) -> str:
        lines = ["$tblNm:"]
        for sig_name, data in signals.items():
            lines.append(f"  - signal: {sig_name}")
            lines.append(f"    nbits: {data['nbits']}")
            lines.append(f"    changes:")
            for t, v in data["changes"]:
                lines.append(f"      - [{t}, {v}]")
        return getTmpltStr("\n".join(lines) + "\n", table_name)


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    import argparse
    ap = argparse.ArgumentParser(description="Wave Display Interface")
    ap.add_argument("circuit", nargs="?", help="Circuit name, e.g. TB_DVDR4")
    ap.add_argument("--config", default=str(PROJECT_ROOT / "Config.yaml"), help="Path to Config.yaml")
    args = ap.parse_args()

    app = QApplication(sys.argv)
    win = WaveDisplay(args.config, args.circuit)
    win.show()
    _center_on_screen(win)
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
