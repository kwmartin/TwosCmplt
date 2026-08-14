from __future__ import annotations

import math
import sys
from pathlib import Path

from PySide6.QtCore import QPoint, QPointF, QRectF, Qt, Signal
from PySide6.QtGui import (
    QAction, QColor, QContextMenuEvent, QFont, QFontMetrics, QKeySequence,
    QMouseEvent, QPainter, QPen, QShortcut, QWheelEvent,
)
from PySide6.QtWidgets import (
    QApplication,
    QFileDialog,
    QLabel,
    QMainWindow,
    QMenu,
    QMessageBox,
    QScrollBar,
    QStyle,
    QVBoxLayout,
    QWidget,
)

from lib.glbls import rd_yml

# SimLib/lib is inserted as a bare directory (not as a `lib` package) so its
# modules resolve as top-level names -- must not collide with this file's
# own `lib` package (imported just above for lib.glbls). Neither
# wave_data_model.py nor its siblings there import anything as `lib.xxx`
# internally, so there's no name collision risk in either direction.
_SIMLIB_LIB = '/home/martin/IC_Design/Testbenches/NgSpice/SimLib/lib'
if _SIMLIB_LIB not in sys.path:
    sys.path.insert(0, _SIMLIB_LIB)

from wave_data_model import (
    Segment,
    snap01,
    build_constants_map,
    expr_to_abs_time,
    expr_to_period_units,
    transitions_to_segments,
    WaveRow,
    ClockWaveRow,
    DigitalWaveRow,
)
from wave_selection import SelectionModel
from wave_reorder import move_block_up, move_block_down
from wave_context_menu import show_label_menu

SAVE_LOCATION = "../Resources/SimSpcs"

LEFT = 0
RIGHT = 1


# ---------------------------------------------------------------------------
# Row label widget (read-only, clickable for selection)
# ---------------------------------------------------------------------------

class RowLabel(QLabel):
    clicked = Signal(object, object)  # wave, Qt.KeyboardModifiers

    def __init__(self, wave: WaveRow, canvas: "WaveformCanvas", parent=None):
        super().__init__(wave.label_text, parent)
        self._wave = wave
        self.canvas = canvas
        self.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        self.setStyleSheet(
            "QLabel {"
            " background:#11161c;"
            " color:#d7e3f4;"
            " padding:2px 8px;"
            " font-size:14px;"
            "}"
        )

    def mousePressEvent(self, event: QMouseEvent):
        self.clicked.emit(self._wave, event.modifiers())
        super().mousePressEvent(event)

    def contextMenuEvent(self, event: QContextMenuEvent):
        self.canvas.show_label_context_menu(self._wave, event.globalPos())


# ---------------------------------------------------------------------------
# Digital waveform canvas (view-only)
# ---------------------------------------------------------------------------

class WaveformCanvas(QWidget):
    cursor_moved = Signal(object)       # emits float (seconds) or None
    cursor_moved_pu = Signal(object)    # emits float (period units) or None
    marker_changed = Signal(object)     # emits float (period units) or None
    view_changed = Signal(float, float)   # left_time, major_grid_px
    label_width_changed = Signal(int)     # label_panel_width
    waves_deleted = Signal(list)          # list of deleted label_text strings

    def __init__(self):
        super().__init__()
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.StrongFocus)

        self.label_panel_width = 150
        self._label_full_width = 150
        self._label_hscroll = 0
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
        self._initial_visible_time: float = 10.0

        self.base_yaml_path: Path | None = None
        self.save_dir: Path | None = None
        self.base_data: dict = {}

        self.constants_list: list = [["PER", 1000]]
        self.constants_map: dict[str, float] = {"PER": 1000.0}
        self.finish_time_expr = "32*PER"
        self.clock_specs: list[dict] = []
        self._preserved_nonclock_waves: list[DigitalWaveRow] = []

        # period_s > 0 when loaded from dat files; used to convert PU → seconds
        self._period_s: float = 0.0
        self._cursor_t: float | None = None   # current cursor time in period units

        common_wave_color = QColor("#7ee787")
        self.wave_pen = QPen(common_wave_color, 2.0)
        self.frame_pen = QPen(QColor("#5ab0d8"), 1.0)
        self.major_grid_pen = QPen(QColor(70, 95, 112), 1)
        self.minor_grid_pen = QPen(QColor(45, 60, 72), 1)
        self.text_pen = QPen(QColor("#9fb3c8"))
        self.tick_pen = QPen(QColor("#9fb3c8"), 1)
        self.axis_text_pen = QPen(QColor("#d7e3f4"))
        self.zero_line_pen = QPen(QColor("#888888"), 1.0)
        self.one_line_pen  = QPen(QColor("#007777"), 1.0)
        self.row_sep_pen   = QPen(QColor("#4a7090"), 1)
        self.cursor_pen = QPen(QColor("#ffd166"), 1, Qt.DashLine)
        self.marker_pen = QPen(QColor("#ef4444"), 2, Qt.SolidLine)

        self._marker_t: float | None = None
        self._dragging_marker: bool = False

        self.waves: list[WaveRow] = []
        self._selection = SelectionModel()

        self.label_widgets: dict[WaveRow, RowLabel] = {}
        self.panning = False
        self.last_mouse_pos = QPoint()
        self.press_pos: QPoint | None = None
        self.press_wave: WaveRow | None = None
        self.press_moved: bool = False
        self.click_drag_threshold: int = 6
        self._syncing: bool = False

        self.hbar = QScrollBar(Qt.Horizontal, self)
        self.vbar = QScrollBar(Qt.Vertical, self)
        self.label_hbar = QScrollBar(Qt.Horizontal, self)
        self.hbar.valueChanged.connect(self._on_hscroll)
        self.vbar.valueChanged.connect(self._on_vscroll)
        self.label_hbar.valueChanged.connect(self._on_label_hscroll)
        self.label_hbar.hide()

        self.overlay = QWidget(self)
        self.overlay.setAttribute(Qt.WA_StyledBackground, True)
        self.overlay.setStyleSheet("background:#11161c; border-right:1px solid #344454;")
        self.overlay.show()

        self.load_default_state()
        self.update_scrollbars()
        self.refresh_label_layout()

    # ------------------------------------------------------------------
    # Loading

    def load_default_state(self):
        self.constants_list = [["PER", 1000]]
        self.constants_map = {"PER": 1000.0}
        self.finish_time_expr = "32*PER"
        self.finishTm = expr_to_period_units(self.finish_time_expr, self.constants_map)
        self.clock_specs = [{"clkNm": "CLK", "initVal": 0, "per": "PER", "delay": 0}]
        self._preserved_nonclock_waves = [
            DigitalWaveRow("INIT", [Segment(0.0, 1.1, 1), Segment(1.1, self.finishTm, 0)]),
        ]
        self._period_s = 0.0
        self.rebuild_waves_from_specs()

    def load_from_dat_rows(
        self, digital_rows: list[dict], period_s: float, finish_s: float
    ) -> None:
        n_periods = finish_s / period_s
        self.constants_list = [["PER", 1000]]
        self.constants_map = {"PER": 1000.0}
        self.finishTm = n_periods
        self.finish_time_expr = f"{int(round(n_periods))}*PER"
        self.clock_specs = []
        self._preserved_nonclock_waves = []
        for row in digital_rows:
            transitions_pu = [t / period_s for t in row['transitions_s']]
            segs = transitions_to_segments(transitions_pu, n_periods, row.get('init', 0))
            self._preserved_nonclock_waves.append(DigitalWaveRow(row['label'], segs))
        self._period_s = period_s
        self.rebuild_waves_from_specs()

    def _preserve_nonclock_waves(self):
        preserved = []
        for wave in self.waves:
            if isinstance(wave, DigitalWaveRow):
                row = DigitalWaveRow(
                    wave.label_text,
                    [Segment(seg.start, seg.end, seg.value) for seg in wave.segments],
                    nbits=wave.nbits,
                )
                row.fmt = wave.fmt
                preserved.append(row)
        self._preserved_nonclock_waves = preserved

    def reconstruct_digital_waves_from_timespcs(self, dct: dict) -> list[DigitalWaveRow]:
        timespcs = dct.get("TimeSpcs", [])
        if not isinstance(timespcs, list) or not timespcs:
            return []

        transitions_by_signal: dict[str, list[tuple[float, int]]] = {}
        signal_order: list[str] = []

        clock_names = {str(clk.get("clkNm")) for clk in self.clock_specs if isinstance(clk, dict)}

        for entry in timespcs:
            if not isinstance(entry, dict):
                continue
            tm_expr = entry.get("tm", 0)
            tm = expr_to_period_units(tm_expr, self.constants_map)
            vls = entry.get("vls", [])
            if not isinstance(vls, list):
                continue
            for item in vls:
                if isinstance(item, (list, tuple)) and len(item) == 2:
                    sig_name = str(item[0])
                    sig_val = int(item[1])
                    if sig_name in clock_names:
                        continue
                    if sig_name not in transitions_by_signal:
                        transitions_by_signal[sig_name] = []
                        signal_order.append(sig_name)
                    transitions_by_signal[sig_name].append((tm, sig_val))

        waves: list[DigitalWaveRow] = []
        for sig_name in signal_order:
            items = transitions_by_signal[sig_name]
            items.sort(key=lambda x: x[0])

            deduped: list[tuple[float, int]] = []
            for tm, val in items:
                tm = snap01(tm)
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
            wave = DigitalWaveRow(sig_name, segments)
            self.normalize_segments(wave)
            waves.append(wave)

        signals_meta = dct.get("Inputs", dct.get("Signals", {}))
        if isinstance(signals_meta, dict):
            for wave in waves:
                if wave.label_text in signals_meta:
                    wave.nbits = max(1, int(signals_meta[wave.label_text]))

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
                DigitalWaveRow("INIT", [Segment(0.0, 1.1, 1), Segment(1.1, self.finishTm, 0)])
            ]

        for wave in self._preserved_nonclock_waves:
            if wave.segments:
                wave.segments[0].start = 0.0
                wave.segments[-1].end = self.finishTm
                self.normalize_segments(wave)
            self.waves.append(wave)

        self._rebuild_label_widgets()

    def _rebuild_label_widgets(self):
        for lbl in self.label_widgets.values():
            lbl.deleteLater()
        self.label_widgets.clear()
        self._selection.clear()
        self._update_label_panel_width()

    def load_base_yaml(self, yml_path: Path):
        dct = rd_yml(str(yml_path))
        if dct is None:
            dct = {}
        if not isinstance(dct, dict):
            raise ValueError(f"{yml_path} does not contain a YAML mapping at top level")

        constants_list = dct.get("Constants", [])
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

        self.base_yaml_path = yml_path
        self.save_dir = yml_path.parent
        self.base_data = dct
        self.constants_list = constants_list
        self.constants_map = constants_map
        self.finish_time_expr = finish_expr
        self.finishTm = finish_tm
        self.clock_specs = clock_specs
        self._period_s = 0.0   # no absolute time reference from spec YAML

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

    def load_sim_yaml(self, yml_path: Path) -> None:
        """Load waveData output from wave_display.py (waveData: [{signal, nbits, changes}])."""
        dct = rd_yml(str(yml_path))
        if not dct or not isinstance(dct, dict):
            return
        entries = next((v for v in dct.values() if isinstance(v, list)), None)
        if entries:
            self._load_sim_entries(entries)

    def load_signals(self, signals: dict) -> None:
        """Load from {name: {nbits, changes[, format]}} dict; times are already in period units."""
        entries = [
            {"signal": name, "nbits": data.get("nbits", 1),
             "changes": data.get("changes", []), "format": data.get("format", "hex")}
            for name, data in signals.items()
        ]
        self._load_sim_entries(entries)

    def _load_sim_entries(self, entries: list) -> None:
        waves: list[DigitalWaveRow] = []
        max_tm: float = 0.0
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            sig_name  = str(entry.get("signal", ""))
            nbits     = max(1, int(entry.get("nbits", 1)))
            raw_chngs = entry.get("changes", [])
            if not sig_name or not raw_chngs:
                continue
            # Sort by (time, simulation_index) to preserve simulation ordering for
            # equal-time events (glitch then settle), then deduplicate keeping the
            # last (settled) value at each timestamp so glitches don't become visible.
            indexed = sorted(
                (float(c[0]), idx, int(c[1]))
                for idx, c in enumerate(raw_chngs)
                if len(c) >= 2
            )
            tvs: list[list] = []
            for t, _, v in indexed:
                if tvs and tvs[-1][0] == t:
                    tvs[-1][1] = v  # same timestamp: keep last (settled) value
                else:
                    tvs.append([t, v])
            if not tvs:
                continue
            if tvs[0][0] > 0.0:
                tvs.insert(0, [0.0, 0])
            max_tm = max(max_tm, tvs[-1][0])
            segments: list[Segment] = []
            for i, (t, v) in enumerate(tvs):
                end = tvs[i + 1][0] if i + 1 < len(tvs) else max_tm
                segments.append(Segment(t, end, v))
            row = DigitalWaveRow(sig_name, segments, nbits=nbits)
            row.fmt = entry.get("format", "hex")
            waves.append(row)

        if not waves:
            return

        finish = max_tm * 1.1 if max_tm > 0 else 100.0
        for wave in waves:
            if wave.segments:
                wave.segments[-1].end = finish

        self.constants_map = {}
        self.clock_specs = []
        self.finishTm = finish
        self._preserved_nonclock_waves = waves
        self.waves = list(waves)
        self._selection.clear()
        self._rebuild_label_widgets()
        self.left_time = 0.0
        self.clamp_left_time()
        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()

    def load_base_yaml_for_name(self, base_name: str) -> str | None:
        base_dir = Path(sys.argv[0]).resolve().parent
        here_path = base_dir / f"{base_name}.yml"
        if here_path.exists():
            self.load_base_yaml(here_path)
            return str(here_path)

        save_dir = (base_dir / SAVE_LOCATION).resolve()
        save_dir.mkdir(parents=True, exist_ok=True)
        save_path = save_dir / f"{base_name}.yml"
        if save_path.exists():
            self.load_base_yaml(save_path)
            return str(save_path)

        return None

    # ------------------------------------------------------------------
    # Geometry helpers

    def showEvent(self, event):
        super().showEvent(event)
        if not self._initial_range_applied and self.width() > 50:
            self._update_label_panel_width()
            self._initial_visible_time = min(10.0, self.finishTm)
            self.show_range(0.0, self._initial_visible_time)
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

    def wave_rect(self, index: int) -> QRectF:
        return QRectF(
            self.waveform_left_x(),
            self.viewport_row_y(index),
            self.waveform_width(),
            self.track_height,
        )

    def wave_at(self, pos: QPoint) -> WaveRow | None:
        x, y = pos.x(), pos.y()
        if x < self.waveform_left_x():
            return None
        for i, wave in enumerate(self.waves):
            if self.wave_rect(i).contains(QPointF(x, y)):
                return wave
        return None

    # ------------------------------------------------------------------
    # View control

    def zoom_full(self):
        visible = self._initial_visible_time
        center_t = self._cursor_t if self._cursor_t is not None else (self.left_time + self.visible_time_span() / 2)
        t0 = center_t - visible / 2
        self.show_range(t0, t0 + visible)

    def pan_to_start(self):
        self.left_time = 0.0
        self.clamp_left_time()
        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()
        self._emit_view()

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

    # ------------------------------------------------------------------
    # Label widgets

    def ensure_label(self, wave: WaveRow) -> RowLabel:
        if wave not in self.label_widgets:
            lbl = RowLabel(wave, self, self.overlay)
            lbl.clicked.connect(self._on_label_clicked)
            self.label_widgets[wave] = lbl
            lbl.show()
        return self.label_widgets[wave]

    def _on_label_clicked(self, wave: WaveRow, modifiers):
        self._selection.toggle(
            wave,
            shift=bool(modifiers & Qt.ShiftModifier),
            ctrl=bool(modifiers & Qt.ControlModifier),
            ordered_items=self.waves,
        )
        self._update_label_selection_styles()
        self.update()

    def _update_label_selection_styles(self):
        for wave, lbl in self.label_widgets.items():
            bg = "#1e3a5f" if wave in self._selection.selected else "#11161c"
            lbl.setStyleSheet(
                "QLabel {"
                f" background:{bg};"
                " color:#d7e3f4;"
                " padding:2px 8px;"
                " font-size:14px;"
                "}"
            )

    def _selected_indices(self) -> list:
        return sorted(i for i, w in enumerate(self.waves) if w in self._selection.selected)

    def move_selection_up(self):
        indices = self._selected_indices()
        if not move_block_up(self.waves, indices):
            return
        self.refresh_label_layout()
        self.update()
        self._scroll_to_show_index(indices[0] - 1)

    def move_selection_down(self):
        indices = self._selected_indices()
        if not move_block_down(self.waves, indices):
            return
        self.refresh_label_layout()
        self.update()
        self._scroll_to_show_index(indices[-1] + 1)

    def delete_selected_waves(self):
        if not self._selection.selected:
            return
        deleted_labels = [w.label_text for w in self._selection.selected]
        for wave in list(self._selection.selected):
            if wave in self.waves:
                self.waves.remove(wave)
            lbl = self.label_widgets.pop(wave, None)
            if lbl:
                lbl.deleteLater()
        self._selection.clear()
        self.update_scrollbars()
        self.refresh_label_layout()
        self.update()
        self.waves_deleted.emit(deleted_labels)

    def show_label_context_menu(self, wave: WaveRow, global_pos):
        sel = [w for w in self.waves if w in self._selection.selected]
        show_label_menu(
            self, wave, global_pos, selected=sel,
            delete_single_fn=self._delete_single_wave,
            delete_bulk_fn=self.delete_selected_waves,
            move_up_fn=self.move_selection_up, move_down_fn=self.move_selection_down,
        )

    def _delete_single_wave(self, wave: WaveRow):
        self._selection.select_only(wave)
        self.delete_selected_waves()

    def _scroll_to_show_index(self, index: int):
        """Scroll vbar so the wave at index is within the visible area."""
        if index < 0 or index >= len(self.waves):
            return
        y = self.row_y(index)
        y_off = self.vbar.value()
        viewport_h = self.height() - self.hbar.height()
        if y - y_off < self.top_margin:
            self.vbar.setValue(max(0, y - self.top_margin))
        elif y + self.track_height - y_off > viewport_h:
            self.vbar.setValue(max(0, y + self.track_height - viewport_h))

    def refresh_label_layout(self):
        sbw = self.style().pixelMetric(QStyle.PixelMetric.PM_ScrollBarExtent)
        hbh = self.hbar.height()
        lhb_shown = not self.label_hbar.isHidden()
        lhbh = sbw if lhb_shown else 0
        overlay_h = max(0, self.height() - hbh - lhbh)
        self.overlay.setGeometry(0, 0, self.label_panel_width, overlay_h)
        if lhb_shown:
            self.label_hbar.setGeometry(0, self.height() - hbh - sbw, self.label_panel_width, sbw)

        lbl_x = 8 - self._label_hscroll
        lbl_w = max(self._label_full_width - 16, self.label_panel_width - 16)
        for i, wave in enumerate(self.waves):
            lbl = self.ensure_label(wave)
            y = self.viewport_row_y(i)
            lbl.setGeometry(lbl_x, y, lbl_w, self.track_height)

    def _measure_max_label_width(self) -> int:
        font = QFont()
        font.setPixelSize(14)
        fm = QFontMetrics(font)
        if not self.waves:
            return 100
        return max(fm.horizontalAdvance(w.label_text) for w in self.waves)

    def _update_label_panel_width(self):
        max_text_w = self._measure_max_label_width()
        needed = max_text_w + 40
        max_allowed = max(150, int(0.25 * self.width()))
        self._label_full_width = max(150, needed)
        if needed <= max_allowed:
            self.label_panel_width = max(150, needed)
            self._label_hscroll = 0
            self.label_hbar.blockSignals(True)
            self.label_hbar.setValue(0)
            self.label_hbar.blockSignals(False)
            self.label_hbar.hide()
        else:
            self.label_panel_width = max_allowed
            self.label_hbar.setRange(0, needed - max_allowed)
            self.label_hbar.setPageStep(max(1, max_allowed // 4))
            self.label_hbar.show()
        self._position_scrollbars()
        self.label_width_changed.emit(self.label_panel_width)

    def _on_label_hscroll(self, value: int):
        self._label_hscroll = value
        self.refresh_label_layout()

    # ------------------------------------------------------------------
    # Resize / scroll

    def _position_scrollbars(self):
        sbw = self.style().pixelMetric(QStyle.PixelMetric.PM_ScrollBarExtent)
        self.vbar.setGeometry(self.width() - sbw, 0, sbw, self.height() - sbw)
        # Confined to the plot region (right of the label column): this bar
        # only pans the time axis, so it must not extend under the labels --
        # doing so implied it scrolled the whole window, labels included.
        # label_panel_width can change outside resizeEvent (see
        # _update_label_panel_width), so this must be called from there too.
        self.hbar.setGeometry(
            self.label_panel_width, self.height() - sbw,
            max(0, self.width() - sbw - self.label_panel_width), sbw,
        )

    def resizeEvent(self, event):
        self._position_scrollbars()

        if self._initial_range_applied:
            visible = max(0.1, self.visible_time_span())
            old_left = self.left_time
            self.major_grid_px = self.waveform_width() / visible
            self.left_time = old_left
            self.clamp_left_time()

        self._update_label_panel_width()
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

    # ------------------------------------------------------------------
    # Segment helpers (needed for loading)

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

    # ------------------------------------------------------------------
    # Mouse / keyboard

    def mousePressEvent(self, event: QMouseEvent):
        self.setFocus(Qt.MouseFocusReason)
        pos = event.position().toPoint()
        self.last_mouse_pos = pos
        self.press_pos = pos
        self.press_moved = False
        ctrl = bool(event.modifiers() & Qt.ControlModifier)
        if (event.button() == Qt.LeftButton and ctrl
                and self._marker_t is not None
                and pos.x() >= self.waveform_left_x()):
            mx = self.time_to_x(self._marker_t)
            if abs(pos.x() - mx) <= 8:
                self._dragging_marker = True
                self.setCursor(Qt.SizeHorCursor)
                return
        if event.button() == Qt.LeftButton and pos.x() >= self.waveform_left_x():
            self.press_wave = self.wave_at(pos)
            self.panning = True
            self.setCursor(Qt.ClosedHandCursor)

    def mouseMoveEvent(self, event: QMouseEvent):
        pos = event.position().toPoint()

        if self.press_pos is not None:
            if (pos - self.press_pos).manhattanLength() > self.click_drag_threshold:
                self.press_moved = True

        if self._dragging_marker and pos.x() >= self.waveform_left_x():
            self._marker_t = max(self.startTm, min(self.finishTm, self.x_to_time(pos.x())))
            self.marker_changed.emit(self._marker_t)
            self.update()
            return

        if pos.x() >= self.waveform_left_x():
            self._cursor_t = self.x_to_time(pos.x())
            t_s = self._cursor_t * self._period_s if self._period_s > 0 else None
            self.cursor_moved.emit(t_s)
            self.cursor_moved_pu.emit(self._cursor_t)
        else:
            if self._cursor_t is not None:
                self._cursor_t = None
                self.cursor_moved.emit(None)
                self.cursor_moved_pu.emit(None)

        if self.panning:
            dx = pos.x() - self.last_mouse_pos.x()
            dy = pos.y() - self.last_mouse_pos.y()
            if abs(dx) > 0:
                self.left_time -= dx / self.major_grid_px
                self.clamp_left_time()
                self.update_scrollbars()
                self.refresh_label_layout()
                self._emit_view()
            if abs(dy) > 0:
                self.vbar.setValue(self.vbar.value() - dy)
            self.last_mouse_pos = pos

        self.update()

    def mouseReleaseEvent(self, event: QMouseEvent):
        if self._dragging_marker:
            self._dragging_marker = False
            self.unsetCursor()
            return

        if self.panning:
            self.panning = False
            self.unsetCursor()

        if event.button() == Qt.LeftButton and not self.press_moved:
            pos = event.position().toPoint()
            if pos.x() >= self.waveform_left_x():
                shift = bool(event.modifiers() & Qt.ShiftModifier)
                if self.press_wave is not None:
                    self._apply_selection(self.press_wave, add=shift)

        self.press_pos = None
        self.press_wave = None
        self.press_moved = False

    def leaveEvent(self, event):
        if self._cursor_t is not None:
            self._cursor_t = None
            self.cursor_moved.emit(None)
            self.cursor_moved_pu.emit(None)
            self.update()
        super().leaveEvent(event)

    def set_cursor_from_time_s(self, t_s):
        if t_s is None or self._period_s <= 0:
            if self._cursor_t is not None:
                self._cursor_t = None
                self.update()
            return
        self._cursor_t = t_s / self._period_s
        self.update()

    def keyPressEvent(self, event):
        if event.modifiers() & Qt.ControlModifier:
            if event.key() == Qt.Key_D:
                self.delete_selected_waves()
                event.accept()
                return
            if event.key() == Qt.Key_Up:
                self.move_selection_up()
                event.accept()
                return
            if event.key() == Qt.Key_Down:
                self.move_selection_down()
                event.accept()
                return
        if event.key() == Qt.Key_Escape:
            self._selection.clear()
            self._update_label_selection_styles()
            self.update()
            event.accept()
            return
        super().keyPressEvent(event)

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
            proposed_major = max(20.0, min(1600.0, old_major * factor))
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
            step = self.track_height + self.track_gap
            self.vbar.setValue(self.vbar.value() - (step if delta > 0 else -step))
            event.accept()

    # ------------------------------------------------------------------
    # Drawing

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
        self.draw_marker(painter)
        self.draw_cursor(painter)

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

            if wave in self._selection.selected:
                bg = QColor("#dbeafe") if getattr(self, '_print_mode', False) else QColor("#1e3a5f")
                painter.fillRect(rect, bg)

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
            painter.drawText(QPointF(self.waveform_left_x() - 24, y_low  + 5), "0")

            painter.setPen(self.wave_pen)

            if isinstance(wave, ClockWaveRow):
                period = wave.period
                delay  = wave.delay
                trans_times: list[float] = []
                if period > 0:
                    half = period / 2.0
                    n = max(1, math.ceil((self.startTm - delay) / half))
                    while True:
                        t_tr = delay + n * half
                        if t_tr > self.finishTm + 1e-9:
                            break
                        if t_tr >= self.startTm - 1e-9:
                            trans_times.append(t_tr)
                        n += 1
                prev_x = self.time_to_x(self.startTm)
                prev_y = y_high if wave.value_for_time(self.startTm) else y_low
                for t_tr in trans_times:
                    x_tr = self.time_to_x(t_tr)
                    painter.drawLine(QPointF(prev_x, prev_y), QPointF(x_tr, prev_y))
                    next_y = y_low if prev_y == y_high else y_high
                    painter.drawLine(QPointF(x_tr, prev_y), QPointF(x_tr, next_y))
                    prev_x = x_tr
                    prev_y = next_y
                painter.drawLine(QPointF(prev_x, prev_y),
                                 QPointF(self.time_to_x(self.finishTm), prev_y))

            elif isinstance(wave, DigitalWaveRow):
                if wave.nbits > 1:
                    self._draw_bus_segments(painter, wave, rect, y_high, y_low)
                else:
                    for idx, s in enumerate(wave.segments):
                        t1 = max(s.start, self.startTm)
                        t2 = min(s.end,   self.finishTm)
                        if t2 <= t1:
                            continue
                        x1 = self.time_to_x(t1)
                        x2 = self.time_to_x(t2)
                        y  = y_high if s.value else y_low
                        painter.drawLine(QPointF(x1, y), QPointF(x2, y))

                        if idx > 0 and self.startTm <= s.start <= self.finishTm:
                            prev = wave.segments[idx - 1]
                            py  = y_high if prev.value else y_low
                            xv  = self.time_to_x(s.start)
                            painter.drawLine(QPointF(xv, py), QPointF(xv, y))

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
        return hex(val)  # default: hex

    def drop_marker_at_cursor(self):
        """Drop the marker at the current cursor position (last known mouse location)."""
        if self._cursor_t is not None:
            self._marker_t = self._cursor_t
            self.marker_changed.emit(self._marker_t)
            self.update()

    def contextMenuEvent(self, event: QContextMenuEvent):
        pos = event.pos()
        if pos.x() < self.waveform_left_x():
            return
        if event.modifiers() & Qt.ControlModifier:
            t = self.x_to_time(pos.x())
            self._marker_t = max(self.startTm, min(self.finishTm, t))
            self._cursor_t = self._marker_t
            self.marker_changed.emit(self._marker_t)
            self.update()
            return
        wave = self.wave_at(pos)
        if not isinstance(wave, DigitalWaveRow) or wave.nbits <= 1:
            return

        menu = QMenu(self)
        formats = [("Hex",           "hex"),
                   ("Decimal",       "dec"),
                   ("Signed Decimal","sdec"),
                   ("Binary",        "bin")]
        for label, fmt in formats:
            act = menu.addAction(label)
            act.setCheckable(True)
            act.setChecked(wave.fmt == fmt)
            act.setData(fmt)

        chosen = menu.exec(event.globalPos())
        if chosen is not None:
            wave.fmt = chosen.data()
            self.update()

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
        major_left  = int(math.floor(t_left))
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

    def draw_cursor(self, painter: QPainter):
        if self._cursor_t is None:
            return
        x = self.time_to_x(self._cursor_t)
        if x < self.waveform_left_x() or x > self.waveform_right_x():
            return
        y_top    = float(self.top_margin)
        y_bottom = float(self.height() - self.hbar.height())
        painter.save()
        painter.setPen(self.cursor_pen)
        painter.drawLine(QPointF(x, y_top), QPointF(x, y_bottom))
        painter.restore()

    def draw_marker(self, painter: QPainter):
        if self._marker_t is None:
            return
        x = self.time_to_x(self._marker_t)
        if x < self.waveform_left_x() or x > self.waveform_right_x():
            return
        y_top    = float(self.top_margin)
        y_bottom = float(self.height() - self.hbar.height())
        painter.save()
        painter.setPen(self.marker_pen)
        painter.drawLine(QPointF(x, y_top), QPointF(x, y_bottom))
        painter.restore()

    def _make_print_pixmap(self):
        from PySide6.QtGui import QPixmap as _QPixmap
        orig = {k: getattr(self, k) for k in (
            'wave_pen', 'frame_pen',
            'major_grid_pen', 'minor_grid_pen',
            'text_pen', 'tick_pen', 'axis_text_pen',
            'zero_line_pen', 'one_line_pen',
        )}
        self.wave_pen           = QPen(QColor("#000080"), 2.0)
        self.frame_pen          = QPen(QColor("#1e4d7a"), 1.0)
        self.major_grid_pen     = QPen(QColor("#94a3b8"), 1)
        self.minor_grid_pen     = QPen(QColor("#cbd5e1"), 1)
        self.text_pen           = QPen(QColor("#1e293b"))
        self.tick_pen           = QPen(QColor("#1e293b"), 1)
        self.axis_text_pen      = QPen(QColor("#0f172a"))
        self.zero_line_pen      = QPen(QColor("#64748b"), 1.0)
        self.one_line_pen       = QPen(QColor("#0f766e"), 1.0)
        self._print_mode = True
        try:
            pix = _QPixmap(self.size())
            pix.fill(Qt.white)
            p = QPainter(pix)
            p.setRenderHint(QPainter.RenderHint.Antialiasing)
            self.draw_grid(p)
            self.draw_waves(p)
            self.draw_axis(p)
            # Draw signal labels (overlay QLabel widgets, not painted by canvas)
            font = p.font()
            font.setPointSize(11)
            p.setFont(font)
            p.setPen(self.text_pen)
            for i, wave in enumerate(self.waves):
                vy = self.viewport_row_y(i)
                label_rect = QRectF(4, vy, self.label_panel_width - 8, self.track_height)
                p.drawText(label_rect, Qt.AlignLeft | Qt.AlignVCenter, wave.label_text)
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


# ---------------------------------------------------------------------------
# Digital-only window
# ---------------------------------------------------------------------------

class DigitalWindow(QMainWindow):
    """Lean window showing only the digital WaveformCanvas, no analog panel."""

    def __init__(self, sim_path: "Path | None" = None):
        super().__init__()
        self.setWindowTitle("Digital Waveform Viewer")
        self.resize(1280, 720)

        self.viewer = WaveformCanvas()

        self._build_menu()

        central = QWidget()
        vbox = QVBoxLayout(central)
        vbox.setContentsMargins(4, 4, 4, 4)
        vbox.setSpacing(0)
        vbox.addWidget(self.viewer)
        self.setCentralWidget(central)

        if sim_path is not None:
            try:
                self.viewer.load_sim_yaml(sim_path)
            except Exception as exc:
                QMessageBox.warning(self, "Load failed", str(exc))

    def _build_menu(self):
        file_menu = self.menuBar().addMenu("File")

        open_action = QAction("Open", self)
        open_action.setShortcut(QKeySequence("Ctrl+O"))
        open_action.triggered.connect(self._open_yaml)
        file_menu.addAction(open_action)

        close_action = QAction("Close", self)
        close_action.setShortcut(QKeySequence("Ctrl+Q"))
        close_action.triggered.connect(self.close)
        file_menu.addAction(close_action)

        waves_menu = self.menuBar().addMenu("Waves")

        move_up_action = QAction("Move Up", self)
        move_up_action.setShortcut(QKeySequence("Ctrl+Up"))
        move_up_action.triggered.connect(self.viewer.move_selection_up)
        waves_menu.addAction(move_up_action)

        move_down_action = QAction("Move Down", self)
        move_down_action.setShortcut(QKeySequence("Ctrl+Down"))
        move_down_action.triggered.connect(self.viewer.move_selection_down)
        waves_menu.addAction(move_down_action)

        zoom_menu = self.menuBar().addMenu("Zoom")

        full_action = QAction("Full\tCtrl+F", self)
        full_action.triggered.connect(self.viewer.zoom_full)
        zoom_menu.addAction(full_action)
        QShortcut(QKeySequence("Ctrl+F"), self.viewer,
                  context=Qt.WidgetShortcut).activated.connect(self.viewer.zoom_full)

        pan_action = QAction("Pan to Start\tCtrl+0", self)
        pan_action.triggered.connect(self.viewer.pan_to_start)
        zoom_menu.addAction(pan_action)
        QShortcut(QKeySequence("Ctrl+0"), self.viewer,
                  context=Qt.WidgetShortcut).activated.connect(self.viewer.pan_to_start)

    def _open_yaml(self):
        base = Path(sys.argv[0]).resolve().parent
        flnm, _ = QFileDialog.getOpenFileName(
            self, "Open", str(base), "YAML Files (*.yml *.yaml)"
        )
        if not flnm:
            return
        try:
            self.viewer.load_sim_yaml(Path(flnm))
            self.statusBar().showMessage(f"Loaded {flnm}", 5000)
        except Exception as exc:
            QMessageBox.critical(self, "Load failed", str(exc))


def display_digital(sim_path: "Path | None" = None) -> None:
    """Launch a digital-only waveform viewer.  Creates a QApplication if needed."""
    app = QApplication.instance() or QApplication(sys.argv)
    win = DigitalWindow(sim_path=sim_path)
    win.show()
    app.exec()


def display_analog() -> None:
    """Not implemented in this copy — analog modules are not available here."""
    raise NotImplementedError("display_analog is not available in the tools copy of wave_view.py")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    pos_args = [a for a in sys.argv[1:] if not a.startswith("--")]
    arg = pos_args[0] if pos_args else None
    sim_path: Path | None = None
    if arg:
        full = Path(arg)
        if full.is_absolute() and full.suffix in (".yml", ".yaml") and full.exists():
            sim_path = full
    w = DigitalWindow(sim_path=sim_path)
    w.show()
    sys.exit(app.exec())
