# help_viewer.py

from pathlib import Path

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QAction, QDesktopServices, QFont, QTextOption
from PySide6.QtWidgets import (
    QApplication,
    QMainWindow,
    QMessageBox,
    QTextBrowser,
    QToolBar,
)


class MarkdownHelpWindow(QMainWindow):
    def __init__(self, md_path: str | Path, parent=None):
        super().__init__(parent)

        self.md_path = Path(md_path).resolve()
        self.setWindowTitle("Waveform Input-Signal Editor – Help")
        self.resize(920, 760)

        self.viewer = QTextBrowser(self)
        self.viewer.setReadOnly(True)
        self.viewer.setOpenLinks(False)
        self.viewer.setOpenExternalLinks(False)
        self.viewer.anchorClicked.connect(self._open_link)

        font = QFont()
        font.setPointSize(11)
        self.viewer.setFont(font)

        self.viewer.document().setDefaultTextOption(
            QTextOption(Qt.AlignmentFlag.AlignLeft)
        )

        self.viewer.setStyleSheet(
            """
            QTextBrowser {
                background: #f7f7f7;
                color: #202020;
                border: none;
                padding: 24px 32px 24px 32px;
                selection-background-color: #cfe8ff;
                line-height: 1.35;
            }
            """
        )

        self.setCentralWidget(self.viewer)

        toolbar = QToolBar("Help", self)
        toolbar.setMovable(False)
        self.addToolBar(toolbar)

        reload_action = QAction("Reload", self)
        reload_action.triggered.connect(self.load_markdown)
        toolbar.addAction(reload_action)

        open_external_action = QAction("Open in Browser", self)
        open_external_action.triggered.connect(self.open_in_browser)
        toolbar.addAction(open_external_action)

        self.load_markdown()

    def load_markdown(self):
        if not self.md_path.exists():
            QMessageBox.warning(
                self,
                "Help not found",
                f"Cannot find documentation file:\n{self.md_path}",
            )
            return

        try:
            text = self.md_path.read_text(encoding="utf-8")
        except Exception as exc:
            QMessageBox.critical(
                self,
                "Read error",
                f"Could not read help file:\n{self.md_path}\n\n{exc}",
            )
            return

        self.viewer.setMarkdown(text)
        self.statusBar().showMessage(str(self.md_path), 5000)

    def _open_link(self, url: QUrl):
        if url.isRelative():
            resolved = self.md_path.parent / url.toString()
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(resolved)))
        else:
            QDesktopServices.openUrl(url)

    def open_in_browser(self):
        QDesktopServices.openUrl(QUrl.fromLocalFile(str(self.md_path)))


if __name__ == "__main__":
    import sys

    app = QApplication(sys.argv)
    md_file = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("wv_edit.md")
    win = MarkdownHelpWindow(md_file)
    win.show()
    sys.exit(app.exec())