# Viewing the TwosCmplt documentation

## Swift DocC pages (library and examples)

**Quick way: type `twosdocs`** in any terminal (alias in `~/.bash_aliases`, runs
`scripts/docs.sh serve`). It starts a background web server on port 8123 if one
isn't running and opens the examples page.

Why a server: DocC pages load their content as JSON, which browsers refuse for
`file://` pages, so opening `index.html` directly shows a blank page.

Pages (replace 8123 with your port if you start a server by hand,
e.g. `python3 -m http.server 8000 --directory docs`):

| Documentation                     | URL |
|-----------------------------------|-----|
| Examples (filters, CORDICs, coeff. multiply) | <http://localhost:8123/ExamplesDoc/documentation/examplesdoc/> |
| TwosCmplt library                 | <http://localhost:8123/TwosCmplt/documentation/twoscmplt/> |
| SharedTypes (`TwoCmplt`, `States`) | <http://localhost:8123/SharedTypes/documentation/sharedtypes/> |
| CoeffMltply example               | <http://localhost:8123/CoeffMltply/documentation/coeffmltply/> |

## Rebuilding the DocC pages

All at once: `scripts/docs.sh build`. Or one at a time, from the repository
root; each writes `docs/<Target>/`:

```bash
./scripts/build-examples-doc.sh          # docs/ExamplesDoc (ExamplesDoc + TwosCmplt)
./scripts/build-doc.sh TwosCmplt         # docs/TwosCmplt
./scripts/build-doc.sh SharedTypes       # docs/SharedTypes
./scripts/build-doc.sh CoeffMltply       # docs/CoeffMltply
```

Live preview while editing a `.docc` catalogue (rebuilds on save, prints its URL):

```bash
swift package --disable-sandbox preview-documentation --target ExamplesDoc
```

Sources of these pages: `ExamplesDoc/ExamplesDoc.docc/`,
`Sources/TwosCmplt/TwosCmplt.docc/`, `Sources/SharedTypes/SharedTypes.docc/`,
`Examples/CoeffMltply/CoeffMltply.docc/`, plus `///` comments in the Swift code.

## Doxygen pages (C++-style API index)

`docs/build/html/index.html` opens directly in a browser (no server needed).
Rebuild with `doxygen Doxyfile` from the repository root.

## Printable PDFs

`scripts/docs.sh pdf` (about a minute) makes both:

- `docs/TwosCmplt_Articles.pdf`: the DocC articles (examples, filters,
  CORDICs, library notes, CircDef) with figures. Which articles, and their
  order, are set in `docs/pdf_articles.yaml`; built by `scripts/docs_pdf.py`.
- `docs/build/latex/refman.pdf`: the Doxygen API reference.

Unicode symbols pdflatex can't print (→, ≥, ✓, …) are mapped in
`docs/unicode_chars.sty`; add a line there if a new one breaks the build.

## Running the examples

```bash
swift run Filter3A        # any example target in Examples/
swift run SimRun QD_DDFS5 Config.yaml
```

SimRun debugging notes (VS Code breakpoints): `notes/SimRun_debugging.md`.

## Other notes (Markdown, repository root)

`Simulation.md`, `SIMULATION_ALGORITHM.md`, `SIM_TIMING.md`, `Design_Flow.md`,
`Power_Minimize.md`; waveform viewer: `tools/README.md`, `tools/wave_display.md`.
