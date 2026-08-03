from __future__ import annotations

import copy
import math
import re
import string
import sys
from dataclasses import dataclass
from pathlib import Path

from PySide6.QtCore import QEvent, QPoint, QPointF, QRectF, Qt, Signal
from PySide6.QtGui import (
    QAction, QColor, QContextMenuEvent, QFont, QFontMetrics,
    QKeySequence, QMouseEvent, QPainter, QPen, QWheelEvent,
)
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMenu,
    QMessageBox,
    QPushButton,
    QRadioButton,
    QScrollBar,
    QSpinBox,
    QStyle,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from help_viewer import MarkdownHelpWindow
from lib.glbls import *

SAVE_LOCATION = "../Resources/SimSpcs"

LEFT = 0
RIGHT = 1
NO_HANDLE = -1


@dataclass
class Segment:
    start: float
    end: float
    value: int


def alpha_name_from_index(idx: int) -> str:
    letters = string.ascii_uppercase
    result = ""
    while True:
        result = letters[idx % 26] + result
        idx = idx // 26 - 1
        if idx < 0:
            break
    return result


def snap01(t: float) -> float:
    return round(t * 10.0) / 10.0


def fmt_tm_expr(t: float, per_name: str = "PER") -> int | str:
    t = snap01(t)
    if abs(t) < 1e-12:
        return 0
    if abs(t - round(t)) < 1e-9:
        return f"{int(round(t))}*{per_name}"
    return f"{t:.1f}*{per_name}"


def _parse_int_value(value) -> int:
    """Parse an integer value, handling TwosCmplt 'Nbits_h_hexdigits' format."""
    if isinstance(value, int):
        return value
    s = str(value).strip()
    if 'h' in s:
        return int(s.split('h', 1)[1], 16)
    return int(s, 0)


def _parse_bus_value(value) -> tuple[int, int]:
    """Parse a value, returning (int_value, nbits). Handles 'Nbits_h_hexdigits' format."""
    if isinstance(value, int):
        return value, 1
    s = str(value).strip()
    if 'h' in s:
        parts = s.split('h', 1)
        try:
            nbits = int(parts[0])
        except ValueError:
            nbits = 1
        return int(parts[1], 16), nbits
    return int(s, 0), 1


def _mask_to_nbits(value: int, nbits: int) -> int:
    if nbits <= 0:
        return value
    return int(value) & ((1 << nbits) - 1)


def build_constants_map(constants_list) -> dict[str, float]:
    constants_map: dict[str, float] = {}
    for item in constants_list or []:
        if isinstance(item, (list, tuple)) and len(item) == 2:
            nm, val = item
            if isinstance(val, (int, float)):
                constants_map[str(nm)] = float(val)
    return constants_map


def expr_to_abs_time(value, constants: dict[str, float]) -> float:
    if isinstance(value, (int, float)):
        return float(value)

    s = str(value).strip()
    if s == "":
        raise ValueError("empty expression")

    if s in constants:
        return float(constants[s])

    if re.fullmatch(r"[+-]?\d+(\.\d+)?", s):
        return float(s)

    m = re.fullmatch(r"([+-]?\d+(\.\d+)?)\s*\*\s*([A-Za-z_]\w*)", s)
    if m:
        mult = float(m.group(1))
        name = m.group(3)
        if name not in constants:
            raise ValueError(f"unknown constant '{name}' in expression '{s}'")
        return mult * float(constants[name])

    raise ValueError(f"unsupported expression '{s}'")


def expr_to_period_units(value, constants: dict[str, float]) -> float:
    per_val = float(constants["PER"])
    abs_val = expr_to_abs_time(value, constants)
    return abs_val / per_val


class LabelEdit(QLineEdit):
    focused = Signal(object)

    def __init__(self, wave: "WaveRow", parent=None):
        super().__init__(parent)
        self.wave = wave
        self.setText(wave.label_text)
        self.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        self.textChanged.connect(self._on_text_changed)
        self._set_normal_style()

    def _on_text_changed(self, text: str):
        self.wave.label_text = text

    def focusInEvent(self, event):
        self.focused.emit(self.wave)
        super().focusInEvent(event)

    def _set_normal_style(self):
        self.setStyleSheet(
            "QLineEdit {"
            " background:#1b2430;"
            " color:#d7e3f4;"
            " border:1px solid #4a5b6c;"
            " padding:2px 8px 2px 8px;"
            " font-size:14px;"
            "}"
            "QLineEdit:focus {"
            " border:2px solid #ffd166;"
            "}"
        )

    def _set_selected_style(self):
        self.setStyleSheet(
            "QLineEdit {"
            " background:#2a2417;"
            " color:#fff0c2;"
            " border:2px solid #ffd166;"
            " padding:2px 8px 2px 8px;"
            " font-size:14px;"
            "}"
        )

    def set_selected(self, selected: bool):
        if selected:
            self._set_selected_style()
        else:
            self._set_normal_style()


class ValueEditDialog(QDialog):
    """Dialog to set the value of a multi-bit segment (or promote a 1-bit signal)."""

    def __init__(self, signal_name: str, current_value: int, nbits: int, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Set Segment Value")
        self.setModal(True)
        self.result_value: int | None = None
        self.result_nbits: int | None = None

        self.setStyleSheet(
            "QDialog { background:#11161c; }"
            "QLabel  { color:#d7e3f4; }"
            "QLineEdit { background:#1b2430; color:#d7e3f4;"
            "            border:1px solid #344454; padding:4px; }"
            "QPushButton { background:#1b2430; color:#d7e3f4;"
            "              border:1px solid #344454; padding:4px 14px; }"
            "QPushButton:hover { background:#2a3a50; }"
        )

        layout = QVBoxLayout(self)
        layout.setSpacing(8)

        lbl = QLabel(
            f"Signal: <b>{signal_name}</b>  —  current: {hex(current_value)}  "
            f"({nbits} bit{'s' if nbits != 1 else ''})"
        )
        lbl.setStyleSheet("color:#d7e3f4;")
        layout.addWidget(lbl)

        hint = QLabel("Enter value: decimal, 0b…, 0x…, or 0o…")
        hint.setStyleSheet("color:#7a95b0; font-size:11px;")
        layout.addWidget(hint)

        self._edit = QLineEdit()
        self._edit.installEventFilter(self)
        self._edit.setFocus()
        layout.addWidget(self._edit)

        self._err_lbl = QLabel("")
        self._err_lbl.setStyleSheet("color:#ff6b6b; font-size:11px;")
        layout.addWidget(self._err_lbl)

        btn_row = QHBoxLayout()
        enter_btn = QPushButton("Enter")
        cancel_btn = QPushButton("Cancel")
        enter_btn.setDefault(True)
        btn_row.addWidget(enter_btn)
        btn_row.addWidget(cancel_btn)
        layout.addLayout(btn_row)

        enter_btn.clicked.connect(self._accept)
        cancel_btn.clicked.connect(self.reject)
        self._edit.returnPressed.connect(self._accept)

    def eventFilter(self, obj, event):
        if (
            obj is self._edit
            and event.type() == QEvent.Type.KeyPress
            and event.key() == Qt.Key_V
            and not (event.modifiers() & Qt.ControlModifier)
        ):
            return True
        return super().eventFilter(obj, event)

    def _accept(self):
        text = self._edit.text().strip()
        try:
            value = int(text, 0)
            if value < 0:
                raise ValueError("value must be non-negative")
            nbits = self._bits_from_literal(text)
            self.result_value = value
            self.result_nbits = nbits
            self.accept()
        except ValueError as exc:
            self._err_lbl.setText(str(exc))

    @staticmethod
    def _bits_from_literal(s: str) -> int:
        s = s.strip()
        lo = s.lower()
        if lo.startswith("0b"):
            digits = lo[2:]
            return max(1, len(digits)) if digits else 1
        if lo.startswith("0x"):
            digits = lo[2:]
            return max(1, len(digits) * 4) if digits else 4
        if lo.startswith("0o"):
            digits = lo[2:]
            return max(1, len(digits) * 3) if digits else 3
        val = int(s, 0)
        return max(1, val.bit_length())


class WaveRow:
    def __init__(self, label_text: str):
        self.label_text = label_text


class ClockWaveRow(WaveRow):
    def __init__(self, label_text: str = "CLK"):
        super().__init__(label_text)
        self.start_high = False
        self.per_expr = "PER"
        self.delay_expr = 0
        self.period = 1.0
        self.delay = 0.0

    def value_for_time(self, t: float) -> int:
        init_val = 1 if self.start_high else 0

        if t < self.delay:
            return init_val

        local_t = t - self.delay
        if self.period <= 0:
            return init_val

        phase = local_t % self.period
        if phase < (0.5 * self.period):
            return init_val
        return 1 - init_val

    def toggle_start_value(self):
        self.start_high = not self.start_high


class DigitalWaveRow(WaveRow):
    def __init__(self, label_text: str, segments: list[Segment], editable: bool,
                 nbits: int = 1):
        super().__init__(label_text)
        self.segments = segments
        self.editable = editable
        self.nbits = nbits
        self.fmt: str = "hex"

    def toggle_start_value(self):
        if self.nbits > 1:
            return
        for seg in self.segments:
            seg.value = 1 - seg.value


class WaveformCanvas(QWidget):
    selection_changed = Signal()
    waves_changed = Signal()
    undo_changed = Signal()
    view_changed = Signal(float, float)   # left_time, major_grid_px
    cursor_moved_pu = Signal(object)      # emits float (period units) or None

    def __init__(self):
        super().__init__()
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.StrongFocus)

        self.label_panel_width = 150
        self.right_margin = 20
        self.top_margin = 30
        self.bottom_margin = 8
        self.track_height = 27
        self.track_gap = 4
        self.axis_gap = 20

        self.startTm = 0.0
        self.finishTm = 32.0
        self.left_time = 0.0
        self.major_grid_px = 80.0
        self.minor_divisions = 4
        self.min_segment_time = 0.1
        self._initial_range_applied = False

        self.base_yaml_path: Path | None = None
        self.save_dir: Path | None = None
        self.base_data: dict = {}
        self.constants_list: list = [["PER", 1000]]
        self.constants_map: dict[str, float] = {"PER": 1000.0}
        self.finish_time_expr = "32*PER"
        self.clock_specs: list[dict] = []
        self._signal_nbits: dict[str, int] = {}
        self._preserved_nonclock_waves: list[DigitalWaveRow] = []

        common_wave_color = QColor("#7ee787")
        self.wave_pen = QPen(common_wave_color, 2.0)
        self.frame_pen = QPen(QColor("#cbd5e1"), 1.5)
        self.major_grid_pen = QPen(QColor(70, 95, 112), 1)
        self.minor_grid_pen = QPen(QColor(45, 60, 72), 1)
        self.text_pen = QPen(QColor("#9fb3c8"))
        self.tick_pen = QPen(QColor("#9fb3c8"), 1)
        self.axis_text_pen = QPen(QColor("#d7e3f4"))
        self.selected_outline_pen = QPen(QColor("#ffd166"), 2.0)
        self.handle_overlay_brush = QColor(126, 231, 135, 50)
        self.zero_line_pen = QPen(QColor("#888888"), 1.0)
        self.one_line_pen  = QPen(QColor("#007777"), 1.0)
        self.row_sep_pen   = QPen(QColor("#4a7090"), 1)

        self.waves: list[WaveRow] = []
        self.selected_wave: WaveRow | None = None
        self.selected_waves: set = set()
        self.current_action_key: str | None = None
        self._shift_held = False
        self.next_added_signal_index = 0

        self.label_edits: dict[WaveRow, LabelEdit] = {}
        self.selected_handle = (NO_HANDLE, -1)
        self.dragging_wave: DigitalWaveRow | None = None
        self.panning = False
        self.last_mouse_pos = QPoint()
        self.press_pos: QPoint | None = None
        self.press_wave: WaveRow | None = None
        self.press_moved = False
        self.click_drag_threshold = 6
        self._syncing: bool = False

        self._undo_stack: list = []
        self._redo_stack: list = []

        self.hbar = QScrollBar(Qt.Horizontal, self)
        self.vbar = QScrollBar(Qt.Vertical, self)
        self.hbar.valueChanged.connect(self._on_hscroll)
        self.vbar.valueChanged.connect(self._on_vscroll)

        self.overlay = QWidget(self)
        self.overlay.setAttribute(Qt.WA_StyledBackground, True)
        self.overlay.setStyleSheet("background:#11161c; border-right:1px solid #344454;")
        self.overlay.show()

        self.load_default_state()
        self.update_scrollbars()
        self.refresh_label_layout()

    def load_default_state(self):
        self.constants_list = [["PER", 1000]]
        self.constants_map = {"PER": 1000.0}
        self.finish_time_expr = "32*PER"
        self.finishTm = expr_to_period_units(self.finish_time_expr, self.constants_map)
        self.clock_specs = [{"clkNm": "CLK", "initVal": 0, "per": "PER", "delay": 0}]
        self._preserved_nonclock_waves = [
            DigitalWaveRow("INIT", [Segment(0.0, 1.1, 1), Segment(1.1, self.finishTm, 0)], editable=True),
            DigitalWaveRow("CNT", [Segment(0.0, 1.2, 0), Segment(1.2, 18.1, 1), Segment(18.1, self.finishTm, 0)], editable=True),
            DigitalWaveRow("A", [Segment(0.0, self.finishTm, 0)], editable=True),
        ]
        self.rebuild_waves_from_specs()

    def _preserve_nonclock_waves(self):
        self._preserved_nonclock_waves = []
        for wave in self.waves:
            if isinstance(wave, DigitalWaveRow):
                dw = DigitalWaveRow(
                    wave.label_text,
                    [Segment(seg.start, seg.end, seg.value) for seg in wave.segments],
                    editable=wave.editable,
                    nbits=wave.nbits,
                )
                dw.fmt = wave.fmt
                self._preserved_nonclock_waves.append(dw)

    # ------------------------------------------------------------------ undo/redo

    def _snapshot(self) -> dict:
        self.sync_clock_specs_from_waves()
        self._preserve_nonclock_waves()
        return {
            "waves": copy.deepcopy(self._preserved_nonclock_waves),
            "clock_specs": copy.deepcopy(self.clock_specs),
        }

    def _restore_snapshot(self, snap: dict):
        self._preserved_nonclock_waves = snap["waves"]
        self.clock_specs = snap["clock_specs"]
        self.rebuild_waves_from_specs()
        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()
        self.waves_changed.emit()

    def _push_undo(self):
        self._undo_stack.append(self._snapshot())
        if len(self._undo_stack) > 100:
            self._undo_stack.pop(0)
        self._redo_stack.clear()
        self.undo_changed.emit()

    def undo(self):
        if not self._undo_stack:
            return
        self._redo_stack.append(self._snapshot())
        snap = self._undo_stack.pop()
        self._restore_snapshot(snap)
        self.undo_changed.emit()

    def redo(self):
        if not self._redo_stack:
            return
        self._undo_stack.append(self._snapshot())
        snap = self._redo_stack.pop()
        self._restore_snapshot(snap)
        self.undo_changed.emit()

    def reconstruct_digital_waves_from_timespcs(self, dct: dict) -> list[DigitalWaveRow]:
        timespcs = dct.get("TimeSpcs", [])
        if not isinstance(timespcs, list) or not timespcs:
            return []

        transitions_by_signal: dict[str, list[tuple[float, int]]] = {}
        signal_order: list[str] = []
        nbits_by_signal: dict[str, int] = {}

        clock_names = {str(clk.get("clkNm")) for clk in self.clock_specs if isinstance(clk, dict)}

        for entry in timespcs:
            if not isinstance(entry, dict):
                # Flat [name, value] entry — treated as initial value at t=0
                if isinstance(entry, (list, tuple)) and len(entry) == 2:
                    sig_name = str(entry[0])
                    if sig_name in clock_names:
                        continue
                    try:
                        sig_val, sig_nbits = _parse_bus_value(entry[1])
                    except (ValueError, TypeError):
                        continue
                    if sig_name not in transitions_by_signal:
                        transitions_by_signal[sig_name] = []
                        signal_order.append(sig_name)
                    nbits_by_signal[sig_name] = sig_nbits
                    existing = transitions_by_signal[sig_name]
                    if not any(abs(t) < 1e-9 for t, _ in existing):
                        existing.append((0.0, sig_val))
                continue

            tm_expr = entry.get("tm", 0)
            tm = expr_to_period_units(tm_expr, self.constants_map)

            vls = entry.get("vls", [])
            if not isinstance(vls, list):
                continue

            for item in vls:
                if isinstance(item, (list, tuple)) and len(item) == 2:
                    sig_name = str(item[0])
                    try:
                        sig_val, sig_nbits = _parse_bus_value(item[1])
                    except (ValueError, TypeError):
                        continue

                    if sig_name in clock_names:
                        continue

                    if sig_name not in transitions_by_signal:
                        transitions_by_signal[sig_name] = []
                        signal_order.append(sig_name)

                    nbits_by_signal[sig_name] = sig_nbits
                    transitions_by_signal[sig_name].append((tm, sig_val))

        waves: list[DigitalWaveRow] = []

        for sig_name in signal_order:
            items = transitions_by_signal[sig_name]
            items.sort(key=lambda x: x[0])

            nb = self._signal_nbits.get(sig_name, nbits_by_signal.get(sig_name, 1))

            deduped: list[tuple[float, int]] = []
            for tm, val in items:
                tm = snap01(tm)
                val = _mask_to_nbits(val, nb)
                if deduped and abs(deduped[-1][0] - tm) < 1e-9:
                    deduped[-1] = (tm, val)
                else:
                    deduped.append((tm, val))

            if not deduped:
                continue

            if deduped[0][0] > 0.0:
                deduped.insert(0, (0.0, deduped[0][1]))
            elif deduped[0][0] < 0.0:
                deduped[0] = (0.0, deduped[0][1])

            segments: list[Segment] = []
            for i, (tm, val) in enumerate(deduped):
                start = tm
                end = deduped[i + 1][0] if i + 1 < len(deduped) else self.finishTm
                if end <= start:
                    continue
                segments.append(Segment(start, end, int(val)))

            if not segments:
                continue

            wave = DigitalWaveRow(sig_name, segments, editable=True, nbits=nb)
            self.normalize_segments(wave)
            waves.append(wave)

        return waves

    def rebuild_waves_from_specs(self):
        self.waves = []

        for clk in self.clock_specs:
            clk_name = str(clk.get("clkNm", "CLK"))
            init_val = int(clk.get("initVal", 0))
            per_expr = clk.get("per", "PER")
            delay_expr = clk.get("delay", 0)

            period = expr_to_period_units(per_expr, self.constants_map)
            delay = expr_to_period_units(delay_expr, self.constants_map)

            cw = ClockWaveRow(clk_name)
            cw.start_high = bool(init_val)
            cw.per_expr = per_expr
            cw.delay_expr = delay_expr
            cw.period = period
            cw.delay = delay
            self.waves.append(cw)

        if not self._preserved_nonclock_waves:
            self._preserved_nonclock_waves = [
                DigitalWaveRow("INIT", [Segment(0.0, 1.1, 1), Segment(1.1, self.finishTm, 0)], editable=True)
            ]

        for wave in self._preserved_nonclock_waves:
            if wave.segments:
                wave.segments[0].start = 0.0
                wave.segments[-1].end = self.finishTm
                self.normalize_segments(wave)
            self.waves.append(wave)

        self._advance_added_name_counter()
        self._rebuild_label_widgets()

    def _advance_added_name_counter(self):
        used = {w.label_text for w in self.waves}
        idx = 0
        while alpha_name_from_index(idx) in used:
            idx += 1
        self.next_added_signal_index = idx

    def _rebuild_label_widgets(self):
        for edit in self.label_edits.values():
            edit.deleteLater()
        self.label_edits.clear()
        self.selected_wave = None
        self.selected_waves = set()

    def showEvent(self, event):
        super().showEvent(event)
        if not self._initial_range_applied and self.width() > 50:
            self.show_range(0.0, min(10.0, self.finishTm))
            self._initial_range_applied = True

    def waveform_left_x(self) -> int:
        return self.label_panel_width

    def waveform_right_x(self) -> int:
        return self.width() - self.vbar.width() - self.right_margin

    def waveform_width(self) -> float:
        return max(1.0, self.waveform_right_x() - self.waveform_left_x())

    def content_height(self) -> int:
        if not self.waves:
            return self.top_margin + self.bottom_margin
        last_y = self.row_y(len(self.waves) - 1)
        return int(last_y + self.track_height + self.bottom_margin)

    def row_y(self, index: int) -> int:
        return self.top_margin + index * (self.track_height + self.track_gap)

    def visible_time_span(self) -> float:
        return self.waveform_width() / self.major_grid_px

    def clamp_left_time(self):
        visible = self.visible_time_span()
        max_left = max(self.startTm, self.finishTm - visible)
        self.left_time = max(self.startTm, min(max_left, self.left_time))

    def time_to_x(self, t: float) -> float:
        return self.waveform_left_x() + (t - self.left_time) * self.major_grid_px

    def x_to_time(self, x: float) -> float:
        return self.left_time + (x - self.waveform_left_x()) / self.major_grid_px

    def y_offset(self) -> int:
        return self.vbar.value()

    def viewport_row_y(self, index: int) -> int:
        return self.row_y(index) - self.y_offset()

    def axis_y(self) -> int:
        return 8  # fixed: always visible at top regardless of vertical scroll

    def next_default_signal_name(self) -> str:
        while True:
            name = alpha_name_from_index(self.next_added_signal_index)
            self.next_added_signal_index += 1
            if all(w.label_text != name for w in self.waves):
                return name

    def create_default_added_wave(self) -> DigitalWaveRow:
        label = self.next_default_signal_name()
        segments = [
            Segment(0.0, 1.0, 0),
            Segment(1.0, self.finishTm, 1),
        ]
        return DigitalWaveRow(label, segments, editable=True)

    def add_wave(self):
        self._push_undo()
        wave = self.create_default_added_wave()
        self.waves.append(wave)
        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()
        self.waves_changed.emit()

    def delete_selected_wave(self):
        if self.selected_wave is None:
            return
        self._push_undo()
        wave = self.selected_wave
        self.selected_wave = None

        edit = self.label_edits.pop(wave, None)
        if edit is not None:
            edit.deleteLater()

        if wave in self.waves:
            self.waves.remove(wave)

        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()
        self.selection_changed.emit()
        self.waves_changed.emit()

    def duplicate_selected_wave(self):
        if not isinstance(self.selected_wave, DigitalWaveRow):
            return
        original = self.selected_wave
        self._push_undo()
        new_wave = DigitalWaveRow(
            original.label_text + "_copy",
            [Segment(s.start, s.end, s.value) for s in original.segments],
            editable=True,
            nbits=original.nbits,
        )
        new_wave.fmt = original.fmt
        nonclock = [w for w in self.waves if isinstance(w, DigitalWaveRow) and w.editable]
        if original in nonclock:
            nonclock.insert(nonclock.index(original) + 1, new_wave)
        else:
            nonclock.append(new_wave)
        self._preserved_nonclock_waves = nonclock
        self.rebuild_waves_from_specs()
        self.update_scrollbars()
        self.refresh_label_layout()
        self.select_wave(new_wave)
        self.update()
        self.waves_changed.emit()

    def set_repeating_pattern(self, parent: QWidget | None = None) -> bool:
        """Open the periodic-pattern editor and repeat the result to finishTm.

        Returns True if a pattern was applied, False otherwise.
        """
        target = self.selected_wave
        if not isinstance(target, DigitalWaveRow) or not target.editable:
            QMessageBox.information(
                parent or self.window(),
                "No editable wave selected",
                "Select an editable input waveform before setting a repeating pattern.",
            )
            return False

        nbits = self._signal_nbits.get(target.label_text, target.nbits)
        target.nbits = nbits
        dlg = PeriodicPatternDialog(
            target.label_text,
            nbits,
            self.finishTm,
            parent=parent or self.window(),
        )
        if dlg.exec() != QDialog.Accepted:
            return False

        pattern = dlg.get_pattern()
        if pattern is None:
            return False

        period_segments, period_length = pattern
        if period_length <= 0:
            return False

        self._push_undo()
        repeated: list[Segment] = []
        k = 0
        while k * period_length < self.finishTm:
            offset = k * period_length
            for s in period_segments:
                start = offset + s.start
                val = _mask_to_nbits(s.value, nbits)
                end = offset + s.end
                if start >= self.finishTm:
                    break
                end = min(end, self.finishTm)
                if end > start:
                    repeated.append(Segment(start, end, val))
            k += 1

        target.segments = repeated
        target.nbits = nbits
        self.normalize_segments(target)
        self.update()
        self.refresh_label_layout()
        self.waves_changed.emit()
        return True

    def generate_counting_sequence(self, parent: QWidget | None = None) -> bool:
        """Open the counting-sequence generator and apply it to the selected wave.

        Returns True if a sequence was applied, False otherwise.
        """
        target = self.selected_wave
        if not isinstance(target, DigitalWaveRow) or not target.editable:
            QMessageBox.information(
                parent or self.window(),
                "No editable wave selected",
                "Select an editable input waveform before generating a counting sequence.",
            )
            return False

        nbits = self._signal_nbits.get(target.label_text, target.nbits)
        target.nbits = nbits
        dlg = GenerateCountingSequenceDialog(
            target.label_text,
            nbits,
            self.finishTm,
            self.constants_map,
            parent=parent or self.window(),
        )
        if dlg.exec() != QDialog.Accepted:
            return False

        result = dlg.get_sequence()
        if result is None:
            return False
        sequence, merge = result
        if not sequence:
            return False

        self._push_undo()

        if merge:
            # Build existing transitions and merge with generated ones
            existing: dict[float, int] = {seg.start: seg.value for seg in target.segments}
            for tm, val in sequence:
                existing[tm] = _mask_to_nbits(val, nbits)
            times = sorted(existing.keys())
            new_segments: list[Segment] = []
            for i, tm in enumerate(times):
                start = tm
                end = times[i + 1] if i + 1 < len(times) else self.finishTm
                if end <= start:
                    continue
                new_segments.append(Segment(start, end, _mask_to_nbits(existing[tm], nbits)))
            target.segments = new_segments
        else:
            # Replace with the generated sequence
            target.segments = []
            for i, (tm, val) in enumerate(sequence):
                end = sequence[i + 1][0] if i + 1 < len(sequence) else self.finishTm
                if end <= tm:
                    continue
                target.segments.append(Segment(tm, end, _mask_to_nbits(val, nbits)))

        self.normalize_segments(target)
        self.update()
        self.refresh_label_layout()
        self.waves_changed.emit()
        return True

    def _open_value_dialog(self, wave: DigitalWaveRow, seg_index: int):
        self.current_action_key = None
        dlg = ValueEditDialog(
            wave.label_text,
            wave.segments[seg_index].value,
            wave.nbits,
            self.window(),
        )
        if dlg.exec() == QDialog.Accepted and dlg.result_value is not None:
            self._push_undo()
            nbits = max(1, dlg.result_nbits)
            wave.nbits = nbits
            wave.segments[seg_index].value = _mask_to_nbits(dlg.result_value, nbits)
            self.clear_selection()
            self.normalize_segments(wave)
            self.update()
            self.waves_changed.emit()

    def _selected_indices(self) -> list:
        return sorted(i for i, w in enumerate(self.waves) if w in self.selected_waves)

    def move_selection_up(self):
        indices = self._selected_indices()
        if not indices or indices[0] == 0:
            return
        self._push_undo()
        above = self.waves.pop(indices[0] - 1)
        self.waves.insert(indices[-1], above)
        self.refresh_label_layout()
        self.update()
        self.waves_changed.emit()

    def move_selection_down(self):
        indices = self._selected_indices()
        if not indices or indices[-1] >= len(self.waves) - 1:
            return
        self._push_undo()
        below = self.waves.pop(indices[-1] + 1)
        self.waves.insert(indices[0], below)
        self.refresh_label_layout()
        self.update()
        self.waves_changed.emit()

    def zoom_full(self):
        self.show_range(0.0, min(10.0, self.finishTm))

    def show_range(self, t0: float, t1: float):
        visible_time = max(0.1, t1 - t0)
        self.major_grid_px = self.waveform_width() / visible_time
        self.left_time = t0
        self.clamp_left_time()
        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()
        self._emit_view()

    def _emit_view(self):
        if not self._syncing:
            self.view_changed.emit(self.left_time, self.major_grid_px)

    def apply_view(self, left_time: float, major_grid_px: float):
        if self._syncing:
            return
        self._syncing = True
        self.major_grid_px = major_grid_px
        self.left_time = left_time
        self.clamp_left_time()
        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()
        self._syncing = False

    def select_wave(self, wave: WaveRow | None):
        self.selected_wave = wave
        self.selected_waves = {wave} if wave is not None else set()
        for w, edit in self.label_edits.items():
            edit.set_selected(w in self.selected_waves)
        self.selection_changed.emit()
        self.update()

    def select_wave_add(self, wave: WaveRow):
        self.selected_wave = wave
        self.selected_waves.add(wave)
        for w, edit in self.label_edits.items():
            edit.set_selected(w in self.selected_waves)
        self.selection_changed.emit()
        self.update()

    def clear_selection(self):
        self.select_wave(None)

    def ensure_label(self, wave: WaveRow):
        if wave not in self.label_edits:
            edit = LabelEdit(wave, self.overlay)
            edit.focused.connect(self.select_wave)
            if isinstance(wave, ClockWaveRow):
                edit.setReadOnly(True)
            self.label_edits[wave] = edit
            edit.show()
        return self.label_edits[wave]

    def refresh_label_layout(self):
        hbh = self.hbar.height()
        overlay_h = max(0, self.height() - hbh)
        self.overlay.setGeometry(0, 0, self.label_panel_width, overlay_h)

        for i, wave in enumerate(self.waves):
            edit = self.ensure_label(wave)
            y = self.viewport_row_y(i)
            edit.setGeometry(8, y, self.label_panel_width - 16, self.track_height)
            edit.set_selected(wave in self.selected_waves)

    def resizeEvent(self, event):
        sbw = self.style().pixelMetric(QStyle.PixelMetric.PM_ScrollBarExtent)
        self.vbar.setGeometry(self.width() - sbw, 0, sbw, self.height() - sbw)
        self.hbar.setGeometry(0, self.height() - sbw, self.width() - sbw, sbw)

        if self._initial_range_applied:
            visible = max(0.1, self.visible_time_span())
            old_left = self.left_time
            self.major_grid_px = self.waveform_width() / visible
            self.left_time = old_left
            self.clamp_left_time()

        self.update_scrollbars()
        self.refresh_label_layout()
        super().resizeEvent(event)

    def update_scrollbars(self):
        visible = self.visible_time_span()
        max_left = max(self.startTm, self.finishTm - visible)
        self.clamp_left_time()

        self.hbar.blockSignals(True)
        self.hbar.setRange(0, 100000)
        if max_left <= self.startTm + 1e-12:
            self.hbar.setValue(0)
            self.hbar.setPageStep(100000)
        else:
            frac = (self.left_time - self.startTm) / (max_left - self.startTm)
            self.hbar.setPageStep(max(1, int(100000 * visible / max(visible, self.finishTm - self.startTm))))
            self.hbar.setValue(int(round(frac * 100000)))
        self.hbar.blockSignals(False)

        viewport_h = max(1, self.height() - self.hbar.height())
        content_h = self.content_height()

        self.vbar.blockSignals(True)
        self.vbar.setRange(0, max(0, content_h - viewport_h))
        self.vbar.setPageStep(viewport_h)
        self.vbar.blockSignals(False)

    def _on_hscroll(self, value: int):
        visible = self.visible_time_span()
        max_left = max(self.startTm, self.finishTm - visible)
        if max_left <= self.startTm + 1e-12:
            self.left_time = self.startTm
        else:
            frac = value / 100000.0
            self.left_time = self.startTm + frac * (max_left - self.startTm)
        self.refresh_label_layout()
        self.update()
        self._emit_view()

    def _on_vscroll(self, _value: int):
        self.refresh_label_layout()
        self.update()

    def snap_time_01(self, t: float) -> float:
        return snap01(t)

    def wave_rect(self, index: int) -> QRectF:
        return QRectF(
            self.waveform_left_x(),
            self.viewport_row_y(index),
            self.waveform_width(),
            self.track_height,
        )

    def handle_at(self, wave: DigitalWaveRow, x: float, y: float) -> tuple[int, int]:
        if not wave.editable:
            return NO_HANDLE, -1
        row_index = self.waves.index(wave)
        rect = self.wave_rect(row_index)
        if not rect.adjusted(-8, 0, 8, 0).contains(QPointF(x, y)):
            return NO_HANDLE, -1

        for i, s in enumerate(wave.segments):
            x1 = self.time_to_x(s.start)
            x2 = self.time_to_x(s.end)
            if i > 0 and abs(x - x1) <= 7:
                return LEFT, i
            if i < len(wave.segments) - 1 and abs(x - x2) <= 7:
                return RIGHT, i
        return NO_HANDLE, -1

    def edge_index_at(self, wave: DigitalWaveRow, x: float, y: float) -> int:
        row_index = self.waves.index(wave)
        rect = self.wave_rect(row_index)
        if not rect.adjusted(-8, 0, 8, 0).contains(QPointF(x, y)):
            return -1

        for i in range(1, len(wave.segments)):
            edge_t = wave.segments[i].start
            xv = self.time_to_x(edge_t)
            if abs(x - xv) <= 6:
                return i
        return -1

    def wave_at(self, pos: QPoint) -> WaveRow | None:
        x = pos.x()
        y = pos.y()
        if x < self.waveform_left_x():
            return None
        for i, wave in enumerate(self.waves):
            if self.wave_rect(i).contains(QPointF(x, y)):
                return wave
        return None

    def click_hits_label_editor(self, pos: QPoint) -> bool:
        child = self.childAt(pos)
        return isinstance(child, QLineEdit)

    def normalize_segments(self, wave: DigitalWaveRow):
        if not wave.segments:
            return

        wave.segments.sort(key=lambda s: (s.start, s.end))
        wave.segments[0].start = self.startTm

        for i, seg in enumerate(wave.segments):
            seg.start = snap01(seg.start)
            seg.end = snap01(seg.end)

            if i == 0:
                seg.start = self.startTm
            else:
                seg.start = wave.segments[i - 1].end

            if seg.end < seg.start + self.min_segment_time:
                seg.end = snap01(seg.start + self.min_segment_time)

        for i in range(len(wave.segments) - 1):
            wave.segments[i + 1].start = wave.segments[i].end

        wave.segments[-1].end = self.finishTm

    def insert_edge(self, wave: DigitalWaveRow, t: float):
        if not wave.editable:
            return

        t = self.snap_time_01(t)
        t = max(self.startTm, min(self.finishTm, t))
        if t <= self.startTm or t >= self.finishTm:
            return

        for i in range(1, len(wave.segments)):
            if abs(wave.segments[i].start - t) < 1e-9:
                return

        for i, seg in enumerate(wave.segments):
            if seg.start < t < seg.end:
                self._push_undo()
                old_end = seg.end
                old_value = seg.value
                seg.end = t
                if wave.nbits == 1:
                    new_value = 1 - old_value
                    wave.segments.insert(i + 1, Segment(t, old_end, new_value))
                    for j in range(i + 2, len(wave.segments)):
                        wave.segments[j].value = 1 - wave.segments[j - 1].value
                else:
                    new_value = old_value + 1
                    wave.segments.insert(i + 1, Segment(t, old_end, new_value))
                self.normalize_segments(wave)
                self.update()
                self.waves_changed.emit()
                return

    def delete_edge(self, wave: DigitalWaveRow, edge_index: int):
        if not wave.editable:
            return
        if edge_index <= 0 or edge_index >= len(wave.segments):
            return
        self._push_undo()
        left = wave.segments[edge_index - 1]
        current = wave.segments[edge_index]
        left.end = current.end
        del wave.segments[edge_index]

        for j in range(edge_index, len(wave.segments)):
            wave.segments[j].value = 1 - wave.segments[j - 1].value

        self.normalize_segments(wave)
        self.update()
        self.waves_changed.emit()

    def move_edge_in_wave(self, wave: DigitalWaveRow, index: int, handle: int, new_t: float):
        new_t = self.snap_time_01(new_t)
        new_t = max(self.startTm, min(self.finishTm, new_t))

        if handle == LEFT and index > 0:
            left = wave.segments[index - 1]
            cur = wave.segments[index]
            lo = left.start + self.min_segment_time
            hi = cur.end - self.min_segment_time
            new_t = max(lo, min(hi, new_t))
            left.end = new_t
            cur.start = new_t

        elif handle == RIGHT and index < len(wave.segments) - 1:
            cur = wave.segments[index]
            right = wave.segments[index + 1]
            lo = cur.start + self.min_segment_time
            hi = right.end - self.min_segment_time
            new_t = max(lo, min(hi, new_t))
            cur.end = new_t
            right.start = new_t

        self.normalize_segments(wave)
        self.update()

    def mousePressEvent(self, event: QMouseEvent):
        self.setFocus(Qt.MouseFocusReason)
        pos = event.position().toPoint()
        self.last_mouse_pos = pos
        self.press_pos = pos
        self.press_wave = self.wave_at(pos)
        self.press_moved = False

        wave = self.press_wave

        if wave is not None:
            shift = (bool(QApplication.keyboardModifiers() & Qt.ShiftModifier)
                     or bool(event.modifiers() & Qt.ShiftModifier)
                     or self._shift_held)
            if shift:
                self.select_wave_add(wave)
            else:
                self.select_wave(wave)

            if isinstance(wave, DigitalWaveRow):
                clicked_t = self.x_to_time(pos.x())

                key_add_mode = self.current_action_key == "a"
                key_del_mode = self.current_action_key == "d"
                mod_add_mode = bool(event.modifiers() & Qt.AltModifier)
                mod_del_mode = bool(event.modifiers() & Qt.ControlModifier)

                add_mode = key_add_mode or mod_add_mode
                del_mode = key_del_mode or mod_del_mode

                if add_mode:
                    self.insert_edge(wave, clicked_t)
                    self.press_wave = None
                    return

                if del_mode:
                    edge_index = self.edge_index_at(wave, pos.x(), pos.y())
                    if edge_index != -1:
                        self.delete_edge(wave, edge_index)
                    self.press_wave = None
                    return

                if self.current_action_key == "v":
                    for idx, seg in enumerate(wave.segments):
                        if seg.start <= clicked_t <= seg.end:
                            self._open_value_dialog(wave, idx)
                            break
                    self.press_wave = None
                    return

                handle, index = self.handle_at(wave, pos.x(), pos.y())
                if handle != NO_HANDLE:
                    self._push_undo()
                    self.dragging_wave = wave
                    self.selected_handle = (handle, index)
                    self.setCursor(Qt.SplitHCursor)
                    self.press_wave = None
                    return

                if self.current_action_key == "t":
                    return  # toggle fires in mouseReleaseEvent; don't start panning

            if event.button() == Qt.LeftButton:
                self.panning = True
                self.setCursor(Qt.ClosedHandCursor)
                return

        if pos.x() < self.waveform_left_x():
            if not self.click_hits_label_editor(pos):
                self.clear_selection()
            self.press_wave = None
            return

        if event.button() == Qt.LeftButton:
            self.panning = True
            self.setCursor(Qt.ClosedHandCursor)
            return

        self.press_wave = None

    def mouseMoveEvent(self, event: QMouseEvent):
        pos = event.position().toPoint()

        if self.press_pos is not None:
            if (pos - self.press_pos).manhattanLength() > self.click_drag_threshold:
                self.press_moved = True

        if pos.x() >= self.waveform_left_x():
            self.cursor_moved_pu.emit(self.x_to_time(pos.x()))
        else:
            self.cursor_moved_pu.emit(None)

        if self.dragging_wave is not None:
            handle, index = self.selected_handle
            t = self.x_to_time(pos.x())
            self.move_edge_in_wave(self.dragging_wave, index, handle, t)
            return

        if self.panning:
            dx = pos.x() - self.last_mouse_pos.x()
            if abs(dx) > 0:
                self.left_time -= dx / self.major_grid_px
                self.clamp_left_time()
                self.update_scrollbars()
                self.refresh_label_layout()
                self.update()
                self._emit_view()
            self.last_mouse_pos = pos
            return

        wave = self.wave_at(pos)
        if isinstance(wave, DigitalWaveRow):
            handle, _ = self.handle_at(wave, pos.x(), pos.y())
            self.setCursor(Qt.SplitHCursor if handle != NO_HANDLE else Qt.ArrowCursor)
        else:
            self.setCursor(Qt.ArrowCursor)

    def mouseReleaseEvent(self, event: QMouseEvent):
        released_wave = self.wave_at(event.position().toPoint())

        did_click_clock = (
            event.button() == Qt.LeftButton
            and isinstance(self.press_wave, ClockWaveRow)
            and released_wave is self.press_wave
            and not self.press_moved
            and self.dragging_wave is None
        )

        did_toggle_digital = (
            event.button() == Qt.LeftButton
            and isinstance(self.press_wave, DigitalWaveRow)
            and released_wave is self.press_wave
            and not self.press_moved
            and self.dragging_wave is None
            and self.current_action_key == "t"
        )

        self.dragging_wave = None
        self.selected_handle = (NO_HANDLE, -1)

        if self.panning:
            self.panning = False
            self.unsetCursor()
        else:
            self.setCursor(Qt.ArrowCursor)

        if did_click_clock:
            self._push_undo()
            self.press_wave.toggle_start_value()
            self.update()
            self.waves_changed.emit()

        if did_toggle_digital:
            self._push_undo()
            self.press_wave.toggle_start_value()
            self.update()
            self.waves_changed.emit()

        self.press_pos = None
        self.press_wave = None
        self.press_moved = False

    def leaveEvent(self, event):
        self.cursor_moved_pu.emit(None)
        super().leaveEvent(event)

    def wheelEvent(self, event: QWheelEvent):
        if event.modifiers() & Qt.ControlModifier:
            event.accept()

            vp_x = float(event.position().x())
            if vp_x < self.waveform_left_x():
                vp_x = float(self.waveform_left_x())

            anchor_t = self.x_to_time(vp_x)
            angle = event.angleDelta().y()
            if angle == 0:
                return

            factor = 1.15 if angle > 0 else (1.0 / 1.15)
            old_major = self.major_grid_px
            proposed_major = max(20.0, min(800.0, old_major * factor))
            min_major = self.waveform_width() / max(0.1, (self.finishTm - self.startTm))
            new_major = max(min_major, proposed_major)

            if abs(new_major - old_major) < 0.01:
                return

            wave_x = vp_x - self.waveform_left_x()
            self.major_grid_px = new_major
            self.left_time = anchor_t - wave_x / self.major_grid_px
            self.clamp_left_time()
            self.update_scrollbars()
            self.refresh_label_layout()
            self.update()
            self._emit_view()
            return

        delta = event.angleDelta().y()
        if delta != 0:
            self.vbar.setValue(self.vbar.value() - delta)

    def keyPressEvent(self, event):
        ctrl = bool(event.modifiers() & Qt.ControlModifier)
        if event.key() == Qt.Key_Z and ctrl:
            self.undo()
            event.accept()
            return
        if event.key() == Qt.Key_Y and ctrl:
            self.redo()
            event.accept()
            return
        if event.key() == Qt.Key_D and ctrl and (event.modifiers() & Qt.ShiftModifier):
            self.duplicate_selected_wave()
            event.accept()
            return
        if event.key() == Qt.Key_D and ctrl:
            self.delete_selected_wave()
            event.accept()
            return
        if event.key() == Qt.Key_Up and ctrl:
            self.move_selection_up()
            event.accept()
            return
        if event.key() == Qt.Key_Down and ctrl:
            self.move_selection_down()
            event.accept()
            return
        if event.key() == Qt.Key_Shift:
            self._shift_held = True
            event.accept()
            return
        if event.key() == Qt.Key_A and not ctrl:
            self.current_action_key = "a"
            event.accept()
            return
        if event.key() == Qt.Key_D and not ctrl:
            self.current_action_key = "d"
            event.accept()
            return
        if event.key() == Qt.Key_T:
            self.current_action_key = "t"
            event.accept()
            return
        if event.key() == Qt.Key_V and not ctrl:
            self.current_action_key = "v"
            event.accept()
            return
        if event.key() == Qt.Key_Escape:
            self.clear_selection()
            self.current_action_key = None
            event.accept()
            return
        super().keyPressEvent(event)

    def keyReleaseEvent(self, event):
        # Ignore synthetic key-release events from X11 auto-repeat so held
        # action keys stay active until the key is physically released.
        if event.isAutoRepeat():
            event.accept()
            return
        if event.key() == Qt.Key_Shift:
            self._shift_held = False
            event.accept()
            return
        if event.key() == Qt.Key_A and self.current_action_key == "a":
            self.current_action_key = None
            event.accept()
            return
        if event.key() == Qt.Key_D and self.current_action_key == "d":
            self.current_action_key = None
            event.accept()
            return
        if event.key() == Qt.Key_T and self.current_action_key == "t":
            self.current_action_key = None
            event.accept()
            return
        if event.key() == Qt.Key_V and self.current_action_key == "v":
            self.current_action_key = None
            event.accept()
            return
        super().keyReleaseEvent(event)

    def _fmt_bus_value(self, val: int, wave: DigitalWaveRow) -> str:
        fmt = wave.fmt
        if fmt == "dec":
            return str(val)
        if fmt == "sdec":
            if val >= (1 << (wave.nbits - 1)):
                val -= (1 << wave.nbits)
            return str(val)
        if fmt == "bin":
            return f"0b{val:0{wave.nbits}b}"
        return hex(val)

    def _draw_bus_segments(self, painter: QPainter, wave: DigitalWaveRow,
                           rect: QRectF, y_high: float, y_low: float):
        SLANT = 5
        BUS_TEXT_PT = 10
        font = painter.font()
        font.setPointSize(BUS_TEXT_PT)
        painter.setFont(font)
        fm = painter.fontMetrics()

        for idx, s in enumerate(wave.segments):
            t1 = max(s.start, self.startTm)
            t2 = min(s.end, self.finishTm)
            if t2 <= t1:
                continue
            x1 = self.time_to_x(t1)
            x2 = self.time_to_x(t2)
            painter.drawLine(QPointF(x1, y_high), QPointF(x2, y_high))
            painter.drawLine(QPointF(x1, y_low),  QPointF(x2, y_low))

            vis_x1 = max(x1, float(self.waveform_left_x()))
            vis_x2 = min(x2, float(self.waveform_right_x()))
            seg_px = vis_x2 - vis_x1
            text = self._fmt_bus_value(s.value, wave)
            tw = fm.horizontalAdvance(text)
            if seg_px >= tw + 6:
                display = text
            elif seg_px >= fm.horizontalAdvance("...") + 4:
                display = "..."
            elif seg_px >= fm.horizontalAdvance("..") + 4:
                display = ".."
            elif seg_px >= fm.horizontalAdvance(".") + 4:
                display = "."
            else:
                display = ""

            if display:
                tx = (vis_x1 + vis_x2) / 2.0 - fm.horizontalAdvance(display) / 2.0
                ty = y_low - 3
                painter.save()
                painter.setPen(self.text_pen)
                painter.setFont(font)
                painter.drawText(QPointF(tx, ty), display)
                painter.restore()

        for i in range(1, len(wave.segments)):
            edge_t = wave.segments[i].start
            if edge_t < self.startTm or edge_t > self.finishTm:
                continue
            xv = self.time_to_x(edge_t)
            painter.drawLine(QPointF(xv - SLANT, y_high), QPointF(xv + SLANT, y_low))
            painter.drawLine(QPointF(xv - SLANT, y_low),  QPointF(xv + SLANT, y_high))

    def contextMenuEvent(self, event: QContextMenuEvent):
        pos = event.pos()
        if pos.x() < self.waveform_left_x():
            return
        wave = self.wave_at(pos)
        if not isinstance(wave, DigitalWaveRow) or not wave.editable:
            return

        self.select_wave(wave)

        menu = QMenu(self)
        count_act = menu.addAction("Generate Counting Sequence…")
        count_act.setData("count")
        repeat_act = menu.addAction("Set Repeating Pattern…")
        repeat_act.setData("repeat")

        if wave.nbits > 1:
            menu.addSeparator()
            fmt_menu = menu.addMenu("Format")
            formats = [("Hex",            "hex"),
                       ("Decimal",        "dec"),
                       ("Signed Decimal", "sdec"),
                       ("Binary",         "bin")]
            for label, fmt in formats:
                act = fmt_menu.addAction(label)
                act.setCheckable(True)
                act.setChecked(wave.fmt == fmt)
                act.setData(fmt)

        chosen = menu.exec(event.globalPos())
        if chosen is None:
            return
        data = chosen.data()
        if data == "count":
            self.generate_counting_sequence()
        elif data == "repeat":
            self.set_repeating_pattern()
        elif data in ("hex", "dec", "sdec", "bin"):
            wave.fmt = data
            self.update()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor("#11161c"))

        waveform_rect = QRectF(
            self.waveform_left_x(),
            0,
            self.waveform_width(),
            self.height() - self.hbar.height(),
        )
        painter.fillRect(waveform_rect, QColor("#11161c"))

        self.draw_grid(painter)
        self.draw_waves(painter)
        self.draw_axis(painter)

    def draw_grid(self, painter: QPainter):
        y_top = 0
        y_bottom = self.height() - self.hbar.height()

        t_left = self.left_time
        t_right = min(self.finishTm, self.left_time + self.visible_time_span())

        major_left = int(math.floor(t_left))
        major_right = int(math.ceil(t_right))

        for major_t in range(major_left, major_right + 1):
            x = self.time_to_x(float(major_t))
            painter.setPen(self.major_grid_pen)
            painter.drawLine(QPointF(x, y_top), QPointF(x, y_bottom))

            if major_t < major_right:
                step = 1.0 / self.minor_divisions
                painter.setPen(self.minor_grid_pen)
                for k in range(1, self.minor_divisions):
                    tm = major_t + k * step
                    if tm < self.startTm or tm > self.finishTm:
                        continue
                    mx = self.time_to_x(tm)
                    painter.drawLine(QPointF(mx, y_top), QPointF(mx, y_bottom))

    def draw_waves(self, painter: QPainter):
        for i, wave in enumerate(self.waves):
            rect = self.wave_rect(i)

            if wave in self.selected_waves:
                painter.fillRect(rect, QColor("#1e3a5f"))

            y_high = rect.top() + self.track_height * 0.25
            y_low  = rect.top() + self.track_height * 0.75

            painter.save()
            painter.setPen(self.row_sep_pen)
            sep_y = rect.bottom() + self.track_gap * 0.5
            painter.drawLine(QPointF(rect.left(), sep_y), QPointF(rect.right(), sep_y))
            painter.setPen(self.zero_line_pen)
            painter.drawLine(QPointF(rect.left(), y_low),  QPointF(rect.right(), y_low))
            painter.setPen(self.one_line_pen)
            painter.drawLine(QPointF(rect.left(), y_high), QPointF(rect.right(), y_high))
            painter.restore()

            painter.setPen(self.text_pen)
            font = painter.font()
            font.setPointSize(10)
            painter.setFont(font)
            painter.drawText(QPointF(self.waveform_left_x() - 24, y_high + 5), "1")
            painter.drawText(QPointF(self.waveform_left_x() - 24, y_low + 5), "0")

            painter.setPen(self.wave_pen)

            if isinstance(wave, ClockWaveRow):
                t = self.startTm
                dt = max(0.02, min(0.05, wave.period / 20.0 if wave.period > 0 else 0.05))
                prev_t = t
                prev_y = y_high if wave.value_for_time(t) else y_low

                while t <= self.finishTm + 1e-9:
                    cur_y = y_high if wave.value_for_time(t) else y_low
                    px = self.time_to_x(prev_t)
                    x = self.time_to_x(t)
                    painter.drawLine(QPointF(px, prev_y), QPointF(x, prev_y))
                    if cur_y != prev_y:
                        painter.drawLine(QPointF(x, prev_y), QPointF(x, cur_y))
                    prev_t = t
                    prev_y = cur_y
                    t = t + dt

                x_end = self.time_to_x(self.finishTm)
                painter.drawLine(QPointF(self.time_to_x(prev_t), prev_y), QPointF(x_end, prev_y))

            elif isinstance(wave, DigitalWaveRow):
                if wave.nbits > 1:
                    self._draw_bus_segments(painter, wave, rect, y_high, y_low)
                else:
                    for idx, s in enumerate(wave.segments):
                        t1 = max(s.start, self.startTm)
                        t2 = min(s.end, self.finishTm)
                        if t2 <= t1:
                            continue

                        x1 = self.time_to_x(t1)
                        x2 = self.time_to_x(t2)
                        y = y_high if s.value else y_low
                        painter.drawLine(QPointF(x1, y), QPointF(x2, y))

                        if idx > 0 and self.startTm <= s.start <= self.finishTm:
                            prev = wave.segments[idx - 1]
                            py = y_high if prev.value else y_low
                            xv = self.time_to_x(s.start)
                            painter.drawLine(QPointF(xv, py), QPointF(xv, y))

                        if wave.editable and idx < len(wave.segments) - 1 and self.startTm <= s.end <= self.finishTm:
                            xv = self.time_to_x(s.end)
                            painter.save()
                            painter.setPen(Qt.NoPen)
                            painter.setBrush(self.handle_overlay_brush)
                            painter.drawRect(QRectF(xv - 3, rect.top(), 6, self.track_height))
                            painter.restore()

    def draw_axis(self, painter: QPainter):
        axis_y = self.axis_y()
        # Fill ruler background to cover grid lines and any waveforms scrolled into the ruler zone
        ruler_bg = Qt.white if getattr(self, '_print_mode', False) else QColor("#11161c")
        painter.fillRect(
            QRectF(self.waveform_left_x(), 0, self.waveform_width(), self.top_margin),
            ruler_bg,
        )
        painter.setPen(self.frame_pen)
        painter.drawLine(
            QPointF(self.waveform_left_x(), axis_y),
            QPointF(self.waveform_right_x(), axis_y),
        )

        t_left = self.left_time
        t_right = min(self.finishTm, self.left_time + self.visible_time_span())
        major_left = int(math.floor(t_left))
        major_right = int(math.ceil(t_right))

        font = painter.font()
        font.setPointSize(10)
        painter.setFont(font)

        for t in range(major_left, major_right + 1):
            if t < self.startTm or t > self.finishTm:
                continue
            x = self.time_to_x(float(t))
            painter.setPen(self.tick_pen)
            painter.drawLine(QPointF(x, axis_y), QPointF(x, axis_y + 6))

            painter.setPen(self.axis_text_pen)
            painter.drawText(QPointF(x + 3, axis_y + 18), f"{t}")

    def _make_print_pixmap(self):
        from PySide6.QtGui import QPixmap as _QPixmap
        orig = {k: getattr(self, k) for k in (
            'wave_pen', 'frame_pen',
            'major_grid_pen', 'minor_grid_pen',
            'text_pen', 'tick_pen', 'axis_text_pen',
            'selected_outline_pen', 'zero_line_pen', 'one_line_pen',
            'handle_overlay_brush',
        )}
        self.wave_pen           = QPen(QColor("#000080"), 2.0)
        self.frame_pen          = QPen(QColor("#1e4d7a"), 1.5)
        self.major_grid_pen     = QPen(QColor("#94a3b8"), 1)
        self.minor_grid_pen     = QPen(QColor("#cbd5e1"), 1)
        self.text_pen           = QPen(QColor("#1e293b"))
        self.tick_pen           = QPen(QColor("#1e293b"), 1)
        self.axis_text_pen      = QPen(QColor("#0f172a"))
        self.selected_outline_pen = QPen(QColor("#0e7490"), 2.0)
        self.zero_line_pen      = QPen(QColor("#64748b"), 1.0)
        self.one_line_pen       = QPen(QColor("#0f766e"), 1.0)
        self.handle_overlay_brush = QColor(22, 101, 52, 50)
        self._print_mode = True
        try:
            pix = _QPixmap(self.size())
            pix.fill(Qt.white)
            p = QPainter(pix)
            p.setRenderHint(QPainter.RenderHint.Antialiasing)
            self.draw_grid(p)
            self.draw_waves(p)
            self.draw_axis(p)
            # Draw signal labels (overlay QLineEdit widgets, not painted by canvas)
            font = p.font()
            font.setPointSize(11)
            p.setFont(font)
            p.setPen(self.text_pen)
            for i, wave in enumerate(self.waves):
                vy = self.viewport_row_y(i)
                label_rect = QRectF(4, vy, self.label_panel_width - 8, self.track_height)
                p.drawText(label_rect, Qt.AlignRight | Qt.AlignVCenter, wave.label_text)
            # Divider between label panel and waveform area
            p.setPen(self.frame_pen)
            p.drawLine(
                QPointF(self.waveform_left_x(), 0),
                QPointF(self.waveform_left_x(), self.height() - self.hbar.height()),
            )
            p.end()
        finally:
            for k, v in orig.items():
                setattr(self, k, v)
            self._print_mode = False
        return pix

    def sync_clock_specs_from_waves(self):
        updated_specs: list[dict] = []

        clocks_by_name: dict[str, ClockWaveRow] = {}
        for wave in self.waves:
            if isinstance(wave, ClockWaveRow):
                clocks_by_name[wave.label_text] = wave

        for spec in self.clock_specs:
            nm = str(spec.get("clkNm", ""))
            if nm in clocks_by_name:
                new_spec = dict(spec)
                new_spec["initVal"] = 1 if clocks_by_name[nm].start_high else 0
                updated_specs.append(new_spec)
            else:
                updated_specs.append(dict(spec))

        self.clock_specs = updated_specs

    def build_tm_spcs(self) -> list[tuple[float, tuple[str, int]]]:
        tm_spcs: list[tuple[float, tuple[str, int]]] = []

        def merge_wave_list(wave_list: list[tuple[float, tuple[str, int]]]):
            nonlocal tm_spcs
            merged: list[tuple[float, tuple[str, int]]] = []
            i = 0
            j = 0

            while i < len(tm_spcs) and j < len(wave_list):
                if tm_spcs[i][0] <= wave_list[j][0]:
                    merged.append(tm_spcs[i])
                    i += 1
                else:
                    merged.append(wave_list[j])
                    j += 1

            if i < len(tm_spcs):
                merged.extend(tm_spcs[i:])
            if j < len(wave_list):
                merged.extend(wave_list[j:])

            tm_spcs = merged

        for wave in self.waves:
            if not isinstance(wave, DigitalWaveRow):
                continue
            if not wave.segments:
                continue

            self.normalize_segments(wave)

            nb = self._signal_nbits.get(wave.label_text, wave.nbits)
            wave_list: list[tuple[float, tuple[str, int]]] = []
            first_seg = wave.segments[0]
            wave_list.append((snap01(0.0), (wave.label_text, _mask_to_nbits(int(first_seg.value), nb))))

            for i in range(1, len(wave.segments)):
                prev_seg = wave.segments[i - 1]
                seg = wave.segments[i]
                trans_time = snap01(prev_seg.end)
                wave_list.append((trans_time, (wave.label_text, _mask_to_nbits(int(seg.value), nb))))

            merge_wave_list(wave_list)

        return tm_spcs

    def build_yaml_dict(self) -> dict:
        self.sync_clock_specs_from_waves()
        tm_spcs = self.build_tm_spcs()

        grouped: dict[float, list[list]] = {}
        for t, (label, value) in tm_spcs:
            t = snap01(t)
            grouped.setdefault(t, []).append([label, value])

        ordered_times = sorted(grouped.keys())
        time_spcs = []
        for t in ordered_times:
            time_spcs.append(
                {
                    "tm": fmt_tm_expr(t, "PER"),
                    "vls": grouped[t],
                }
            )

        data = {
            "Constants": self.constants_list,
            "FinishTime": self.finish_time_expr,
            "TimeSpcs": time_spcs,
        }

        if self.clock_specs:
            data["Clock"] = self.clock_specs

        return data

    def load_base_yaml(self, yml_path: Path):
        dct = rd_yml(str(yml_path))
        if dct is None:
            dct = {}
        if not isinstance(dct, dict):
            raise ValueError(f"{yml_path} does not contain a YAML mapping at top level")

        constants_raw = dct.get("Constants", [])
        # Normalize dict format {PER: 1000} to list format [[PER, 1000]]
        if isinstance(constants_raw, dict):
            constants_list = [[k, v] for k, v in constants_raw.items()]
        else:
            constants_list = constants_raw
        constants_map = build_constants_map(constants_list)
        if "PER" not in constants_map:
            raise ValueError("Base YAML Constants must define PER")

        finish_expr = dct.get("FinishTime", "32*PER")
        finish_tm = expr_to_period_units(finish_expr, constants_map)

        clock_specs = dct.get("Clock", [])
        if clock_specs is None:
            clock_specs = []
        if not isinstance(clock_specs, list):
            raise ValueError("Clock must be a list if present")

        names = set()
        for clk in clock_specs:
            if not isinstance(clk, dict):
                raise ValueError("Each Clock entry must be a mapping")
            clk_name = str(clk.get("clkNm", ""))
            if not clk_name:
                raise ValueError("Each Clock entry must have clkNm")
            if clk_name in names:
                raise ValueError(f"Duplicate clock name '{clk_name}'")
            names.add(clk_name)

            _ = expr_to_period_units(clk.get("per", "PER"), constants_map)
            _ = expr_to_period_units(clk.get("delay", 0), constants_map)

        # Authoritative per-signal bit widths from the specs file (e.g. from gen_verilog_tb.py).
        signal_nbits: dict[str, int] = {}
        for sig_name, nb in (dct.get("Signals") or {}).items():
            try:
                signal_nbits[str(sig_name)] = max(1, int(nb))
            except (ValueError, TypeError):
                continue

        self.base_yaml_path = yml_path
        self.save_dir = yml_path.parent
        self.base_data = dct
        self.constants_list = constants_list
        self.constants_map = constants_map
        self.finish_time_expr = finish_expr
        self.finishTm = finish_tm
        self.clock_specs = clock_specs
        self._signal_nbits = signal_nbits

        reconstructed = self.reconstruct_digital_waves_from_timespcs(dct)
        if reconstructed:
            self._preserved_nonclock_waves = reconstructed
        else:
            self._preserve_nonclock_waves()
            for wave in self._preserved_nonclock_waves:
                if wave.segments:
                    wave.segments[-1].end = self.finishTm
                    self.normalize_segments(wave)

        self.rebuild_waves_from_specs()
        self.left_time = 0.0
        self.clamp_left_time()
        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()

    def load_base_yaml_for_output(self, output_base_name: str):
        base_dir = Path(sys.argv[0]).resolve().parent
        here_path = base_dir / f"{output_base_name}.yml"
        if here_path.exists():
            self.load_base_yaml(here_path)
            return str(here_path)

        save_dir = (base_dir / SAVE_LOCATION).resolve()
        save_dir.mkdir(parents=True, exist_ok=True)
        save_path = save_dir / f"{output_base_name}.yml"
        if save_path.exists():
            self.load_base_yaml(save_path)
            return str(save_path)

        return None


class PeriodicPatternDialog(QDialog):
    """Dialog to edit one period of a waveform and return the repeating unit."""

    DEFAULT_PERIOD_COUNT = 8

    def __init__(
        self,
        signal_name: str,
        nbits: int,
        finish_tm: float,
        parent: QWidget | None = None,
    ):
        super().__init__(parent)
        self.setWindowTitle(f"Periodic Pattern — {signal_name}")
        self.resize(960, 420)

        self.signal_name = signal_name
        self.nbits = nbits
        self.sim_finish_tm = finish_tm
        self.period_count = self.DEFAULT_PERIOD_COUNT

        self._build_ui()
        self._reset_canvas_to_period(self.period_count)

    def _build_ui(self):
        self.setStyleSheet(
            "QDialog { background:#11161c; }"
            "QLabel  { color:#d7e3f4; }"
            "QSpinBox { background:#1b2430; color:#d7e3f4;"
            "           border:1px solid #344454; padding:4px; }"
            "QPushButton { background:#1b2430; color:#d7e3f4;"
            "              border:1px solid #344454; padding:4px 14px; }"
            "QPushButton:hover { background:#2a3a50; }"
        )

        layout = QVBoxLayout(self)
        layout.setSpacing(8)
        layout.setContentsMargins(8, 8, 8, 8)

        top = QHBoxLayout()
        top.addWidget(QLabel(f"Signal: <b>{self.signal_name}</b>"))
        top.addStretch()

        top.addWidget(QLabel("CLK periods per input period:"))
        self._spin = QSpinBox()
        self._spin.setRange(1, 256)
        self._spin.setValue(self.period_count)
        self._spin.valueChanged.connect(self._on_period_count_changed)
        top.addWidget(self._spin)
        layout.addLayout(top)

        info = QLabel(
            "Edit one period below. The pattern will repeat to fill the simulation finish time."
        )
        info.setWordWrap(True)
        info.setStyleSheet("color:#7a95b0; font-size:11px;")
        layout.addWidget(info)

        self.canvas = WaveformCanvas()
        self.canvas.setMinimumHeight(220)
        layout.addWidget(self.canvas, stretch=1)

        self._btn_box = QDialogButtonBox(
            QDialogButtonBox.Ok | QDialogButtonBox.Cancel
        )
        self._btn_box.accepted.connect(self.accept)
        self._btn_box.rejected.connect(self.reject)
        layout.addWidget(self._btn_box)

    def _default_period_segments(self, period_count: int) -> list[Segment]:
        return [
            Segment(0.0, 1.0, 1),
            Segment(1.0, float(period_count), 0),
        ]

    def _reset_canvas_to_period(self, period_count: int):
        self.period_count = period_count
        period_length = float(period_count)

        self.canvas.constants_list = [["PER", 1.0]]
        self.canvas.constants_map = {"PER": 1.0}
        self.canvas.finish_time_expr = f"{period_count}*PER"
        self.canvas.finishTm = period_length
        self.canvas.startTm = 0.0
        self.canvas.clock_specs = [
            {"clkNm": "CLK", "initVal": 0, "per": "PER", "delay": 0}
        ]
        self.canvas._preserved_nonclock_waves = [
            DigitalWaveRow(
                self.signal_name,
                self._default_period_segments(period_count),
                editable=True,
                nbits=self.nbits,
            )
        ]
        self.canvas._initial_range_applied = False
        self.canvas.rebuild_waves_from_specs()
        self.canvas.left_time = 0.0
        self.canvas.clamp_left_time()
        self.canvas.update_scrollbars()
        self.canvas.refresh_label_layout()
        self.canvas.show_range(0.0, min(10.0, period_length))
        self.canvas.update()

    def _on_period_count_changed(self, value: int):
        new_length = float(value)
        old_length = self.canvas.finishTm

        self.canvas.finishTm = new_length
        self.canvas.finish_time_expr = f"{value}*PER"

        for wave in self.canvas.waves:
            if not isinstance(wave, DigitalWaveRow) or not wave.editable:
                continue
            kept: list[Segment] = []
            for s in wave.segments:
                if s.start >= new_length:
                    continue
                end = min(s.end, new_length)
                if end > s.start:
                    kept.append(Segment(s.start, end, s.value))
            if not kept:
                kept = self._default_period_segments(value)
            wave.segments = kept
            self.canvas.normalize_segments(wave)

        self.canvas.update_scrollbars()
        self.canvas.refresh_label_layout()
        self.canvas.show_range(0.0, min(10.0, new_length))
        self.canvas.update()

        if new_length != old_length:
            self.canvas.waves_changed.emit()

    def get_pattern(self) -> tuple[list[Segment], float] | None:
        """Return (one-period segments, period length) or None if no editable wave."""
        for wave in self.canvas.waves:
            if isinstance(wave, DigitalWaveRow) and wave.editable:
                self.canvas.normalize_segments(wave)
                return [Segment(s.start, s.end, s.value) for s in wave.segments], self.canvas.finishTm
        return None


class GenerateCountingSequenceDialog(QDialog):
    """Dialog to generate a counting sequence for one input signal."""

    def __init__(
        self,
        signal_name: str,
        nbits: int,
        finish_tm: float,
        constants_map: dict[str, float],
        parent: QWidget | None = None,
    ):
        super().__init__(parent)
        self.setWindowTitle(f"Generate Counting Sequence — {signal_name}")
        self.resize(420, 260)

        self.signal_name = signal_name
        self.nbits = max(1, nbits)
        self.finish_tm = finish_tm
        self.constants_map = constants_map

        self._build_ui()

    def _build_ui(self):
        self.setStyleSheet(
            "QDialog { background:#11161c; }"
            "QLabel  { color:#d7e3f4; }"
            "QSpinBox { background:#1b2430; color:#d7e3f4;"
            "           border:1px solid #344454; padding:4px; }"
            "QLineEdit { background:#1b2430; color:#d7e3f4;"
            "            border:1px solid #344454; padding:4px; }"
            "QPushButton { background:#1b2430; color:#d7e3f4;"
            "              border:1px solid #344454; padding:4px 14px; }"
            "QPushButton:hover { background:#2a3a50; }"
        )

        layout = QVBoxLayout(self)
        layout.setSpacing(8)
        layout.setContentsMargins(8, 8, 8, 8)

        form = QHBoxLayout()
        form.addWidget(QLabel(f"Signal: <b>{self.signal_name}</b> ({self.nbits} bit{'s' if self.nbits != 1 else ''})"))
        form.addStretch()
        layout.addLayout(form)

        grid = QHBoxLayout()
        grid.addWidget(QLabel("Start:"))
        self._start_spin = QSpinBox()
        self._start_spin.setRange(0, (1 << self.nbits) - 1)
        self._start_spin.setValue(0)
        grid.addWidget(self._start_spin)

        grid.addWidget(QLabel("Final:"))
        self._final_spin = QSpinBox()
        self._final_spin.setRange(1, (1 << self.nbits))
        self._final_spin.setValue(16 if self.nbits == 1 else (1 << self.nbits))
        grid.addWidget(self._final_spin)
        layout.addLayout(grid)

        grid2 = QHBoxLayout()
        grid2.addWidget(QLabel("Time increment:"))
        self._time_edit = QLineEdit("1*PER")
        grid2.addWidget(self._time_edit)

        grid2.addWidget(QLabel("Value increment:"))
        self._var_incr_spin = QSpinBox()
        self._var_incr_spin.setRange(-(1 << self.nbits), (1 << self.nbits))
        self._var_incr_spin.setValue(1)
        grid2.addWidget(self._var_incr_spin)
        layout.addLayout(grid2)

        self._replace_rb = QRadioButton("Replace existing signal entries")
        self._replace_rb.setChecked(True)
        self._replace_rb.setStyleSheet("color:#d7e3f4;")
        self._merge_rb = QRadioButton("Merge with existing entries (per-signal)")
        self._merge_rb.setStyleSheet("color:#d7e3f4;")
        layout.addWidget(self._replace_rb)
        layout.addWidget(self._merge_rb)

        info = QLabel(
            "Values are masked to the signal width. The sequence repeats at the end if "
            "Final exceeds the maximum representable value."
        )
        info.setWordWrap(True)
        info.setStyleSheet("color:#7a95b0; font-size:11px;")
        layout.addWidget(info)

        btn_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btn_box.accepted.connect(self.accept)
        btn_box.rejected.connect(self.reject)
        layout.addWidget(btn_box)

    def get_sequence(self) -> tuple[list[tuple[float, int]], bool] | None:
        """Return (list of (time, value), is_merge) or None if invalid."""
        start = self._start_spin.value()
        final = self._final_spin.value()
        var_incr = self._var_incr_spin.value()
        time_str = self._time_edit.text().strip() or "1*PER"
        try:
            time_incr_f = expr_to_abs_time(time_str, self.constants_map)
        except ValueError:
            QMessageBox.warning(self, "Invalid time increment",
                                f"Could not parse '{time_str}'.")
            return None
        if time_incr_f <= 0:
            QMessageBox.warning(self, "Invalid time increment",
                                "Time increment must be positive.")
            return None
        if final <= start and var_incr > 0:
            QMessageBox.warning(self, "Invalid range",
                                "Final must be greater than Start when increment is positive.")
            return None

        sequence: list[tuple[float, int]] = []
        for i in range(final):
            tm = 0.0 if i == 0 else i * time_incr_f
            val = _mask_to_nbits(start + i * var_incr, self.nbits)
            sequence.append((snap01(tm), val))

        return sequence, self._merge_rb.isChecked()


class MainWindow(QMainWindow):
    def __init__(self, output_base_name: str | None = None):
        super().__init__()
        self.output_base_name = output_base_name or "waveforms"
        self.setWindowTitle("PySide6 Waveform Edge Editor Example")
        self.resize(1280, 560)

        self.editor = WaveformCanvas()
        self._build_menu()

        central = QWidget()
        outer = QVBoxLayout(central)
        outer.setContentsMargins(8, 8, 8, 8)
        outer.setSpacing(6)

        help_label = QLabel(
            "Ctrl+wheel zooms horizontally around the cursor. "
            "Ctrl+F shows 0..10. "
            "Click a CLK waveform to toggle initVal. "
            "Click empty background or press Esc to deselect. "
            "Drag waveform background to pan. "
            "Drag waveform edges to edit. "
            "Existing non-clock signals are reconstructed from TimeSpcs."
            "For non-clock waveforms, <Alt>Click to add a change edge. <Ctl>Click on a change edge to remove it."
            "<Ctl>A to add new waveform. Click on existing waveform and <Ctl>D to delete waveform."
            "Clocks are defined in yaml file in same directory as application, and specified at start up."
        )
        help_label.setWordWrap(True)
        help_label.setStyleSheet(
            "color:#d7e3f4; background:#1b2430; padding:8px; border:1px solid #344454;"
        )
        font = QFont()
        font.setPointSize(10)
        help_label.setFont(font)

        outer.addWidget(help_label)
        outer.addWidget(self.editor, 1)
        self.setCentralWidget(central)

        self.editor.selection_changed.connect(self._update_delete_enabled)
        self.editor.undo_changed.connect(self._update_undo_enabled)
        self._update_delete_enabled()
        self._update_undo_enabled()

        try:
            self.editor.load_base_yaml_for_output(self.output_base_name)
        except Exception as exc:
            QMessageBox.warning(self, "Base YAML load failed", str(exc))

    def save_yaml(self):
        errors = self.editor._validate_waves()
        if errors:
            reply = QMessageBox.question(
                self, "Validation warnings",
                "Warnings:\n" + "\n".join(errors) + "\n\nSave anyway?",
                QMessageBox.Yes | QMessageBox.No,
            )
            if reply != QMessageBox.Yes:
                return
        data = self.editor.build_yaml_dict()

        base_dir = Path(sys.argv[0]).resolve().parent
        out_dir = (base_dir / "../Resources/SimSpcs").resolve()
        out_dir.mkdir(parents=True, exist_ok=True)

        out_file = out_dir / f"{self.output_base_name}.yml"
        wrt_yml(str(out_file), data)
        self.statusBar().showMessage(f"Saved {out_file}", 5000)

    def open_base_yaml(self):
        base_dir = Path(sys.argv[0]).resolve().parent
        start_dir = base_dir
        flnm, _ = QFileDialog.getOpenFileName(
            self,
            "Open",
            str(start_dir),
            "YAML Files (*.yml *.yaml)",
        )
        if not flnm:
            return

        try:
            self.editor.load_base_yaml(Path(flnm))
            self.statusBar().showMessage(f"Loaded base YAML {flnm}", 5000)
        except Exception as exc:
            QMessageBox.critical(self, "Load failed", str(exc))

    def show_help(self):
        base_dir = Path(sys.argv[0]).resolve().parent
        doc_path = base_dir / "wv_edit.md"

        if not hasattr(self, "_help_windows"):
            self._help_windows = []

        help_win = MarkdownHelpWindow(doc_path, self)
        help_win.show()
        help_win.raise_()
        help_win.activateWindow()
        self._help_windows.append(help_win)

    def show_about(self):
        QMessageBox.about(
            self,
            "About Waveform Input-Signal Editor",
            (
                "Waveform Input-Signal Editor\n\n"
                "A Qt-based tool for specifying input signals for digital\n"
                "testbenches and exporting them as YAML for automated\n"
                "testbench generation.\n\n"
                "See Help → Help for full documentation."
            ),
        )

    def _build_menu(self):
        file_menu = self.menuBar().addMenu("File")

        self.open_base_action = QAction("Open", self)
        self.open_base_action.setShortcut(QKeySequence("Ctrl+O"))
        self.open_base_action.triggered.connect(self.open_base_yaml)
        file_menu.addAction(self.open_base_action)

        self.save_action = QAction("Save", self)
        self.save_action.setShortcut(QKeySequence("Ctrl+S"))
        self.save_action.triggered.connect(self.save_yaml)
        file_menu.addAction(self.save_action)

        self.close_action = QAction("Close", self)
        self.close_action.setShortcut(QKeySequence("Ctrl+Q"))
        self.close_action.triggered.connect(self.close)
        file_menu.addAction(self.close_action)

        edit_menu = self.menuBar().addMenu("Edit")

        self.undo_action = QAction("Undo\tCtrl+Z", self)
        self.undo_action.triggered.connect(self.editor.undo)
        self.undo_action.setEnabled(False)
        edit_menu.addAction(self.undo_action)

        self.redo_action = QAction("Redo\tCtrl+Y", self)
        self.redo_action.triggered.connect(self.editor.redo)
        self.redo_action.setEnabled(False)
        edit_menu.addAction(self.redo_action)

        waves_menu = self.menuBar().addMenu("Waves")

        self.add_action = QAction("Add", self)
        self.add_action.setShortcut(QKeySequence("Ctrl+A"))
        self.add_action.triggered.connect(self.editor.add_wave)
        waves_menu.addAction(self.add_action)

        self.delete_action = QAction("Delete", self)
        self.delete_action.setShortcut(QKeySequence("Ctrl+D"))
        self.delete_action.triggered.connect(self.editor.delete_selected_wave)
        waves_menu.addAction(self.delete_action)

        self.duplicate_action = QAction("Duplicate\tCtrl+Shift+D", self)
        self.duplicate_action.triggered.connect(self.editor.duplicate_selected_wave)
        self.duplicate_action.setEnabled(False)
        waves_menu.addAction(self.duplicate_action)

        waves_menu.addSeparator()

        self.count_action = QAction("Generate Counting Sequence…", self)
        self.count_action.triggered.connect(self.editor.generate_counting_sequence)
        self.count_action.setEnabled(False)
        waves_menu.addAction(self.count_action)

        self.repeat_action = QAction("Set Repeating Pattern…", self)
        self.repeat_action.triggered.connect(self.editor.set_repeating_pattern)
        self.repeat_action.setEnabled(False)
        waves_menu.addAction(self.repeat_action)

        waves_menu.addSeparator()

        self.move_up_action = QAction("Move Up", self)
        self.move_up_action.setShortcut(QKeySequence("Ctrl+Up"))
        self.move_up_action.triggered.connect(self.editor.move_selection_up)
        waves_menu.addAction(self.move_up_action)

        self.move_down_action = QAction("Move Down", self)
        self.move_down_action.setShortcut(QKeySequence("Ctrl+Down"))
        self.move_down_action.triggered.connect(self.editor.move_selection_down)
        waves_menu.addAction(self.move_down_action)

        zoom_menu = self.menuBar().addMenu("Zoom")

        self.full_action = QAction("Full", self)
        self.full_action.setShortcut(QKeySequence("Ctrl+F"))
        self.full_action.triggered.connect(self.editor.zoom_full)
        zoom_menu.addAction(self.full_action)

        help_menu = self.menuBar().addMenu("Help")

        self.help_action = QAction("Help", self)
        self.help_action.setShortcut(QKeySequence("F1"))
        self.help_action.triggered.connect(self.show_help)
        help_menu.addAction(self.help_action)

        self.about_action = QAction("About", self)
        self.about_action.triggered.connect(self.show_about)
        help_menu.addAction(self.about_action)

    def _update_delete_enabled(self):
        enabled = self.editor.selected_wave is not None
        self.delete_action.setEnabled(enabled)
        is_digital = isinstance(self.editor.selected_wave, DigitalWaveRow)
        is_editable_digital = (
            is_digital and getattr(self.editor.selected_wave, "editable", False)
        )
        self.duplicate_action.setEnabled(is_digital)
        self.count_action.setEnabled(is_editable_digital)
        self.repeat_action.setEnabled(is_editable_digital)
        self.move_up_action.setEnabled(is_digital)
        self.move_down_action.setEnabled(is_digital)

    def _update_undo_enabled(self):
        self.undo_action.setEnabled(bool(self.editor._undo_stack))
        self.redo_action.setEnabled(bool(self.editor._redo_stack))


if __name__ == "__main__":
    app = QApplication(sys.argv)
    output_base_name = sys.argv[1] if len(sys.argv) > 1 else "waveforms"
    w = MainWindow(output_base_name=output_base_name)
    w.show()
    sys.exit(app.exec())