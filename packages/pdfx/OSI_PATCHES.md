# Local pdfx 2.11.0 patch

Runtime sources copied from the installed pub.dev `pdfx` 2.11.0 package. Original
LICENSE, AUTHORS and README are retained. Dart/Web/iOS/macOS/Windows code is
unchanged. The application uses this package through a path dependency.

Android changes address PDF opening, lag and memory pressure:

- Open/parse PDFs and render cropped textures on one background worker. Platform
  replies and SurfaceProducer lifecycle operations remain on the main thread.
- The private `online.xournal.mobile/pdf-metadata` channel returns all page
  dimensions in one bounded reply instead of an open/close round trip per page.
  It inspects and closes each page sequentially on the existing worker, with
  limits of 10,000 pages and 20,000 units per dimension. Dart validates the reply
  again; other platforms and missing channels retain the per-page fallback.
- Queue document closes after pending texture renders; treat late surface
  callbacks referring to a closed document as an error instead of throwing out
  of the callback.
- Recycle full-page, cropped and texture bitmaps in `finally`, including errors.
  Bound raster and texture dimensions before allocating native bitmaps.
- Unlink only private temporary PDF copies after obtaining the file descriptor;
  Android keeps the descriptor valid. Selected source files are never deleted.
- Clear texture callback state on unregister and drain native resources when
  detaching. Close a file descriptor if PdfRenderer construction fails.
- Report recoverable Java allocation failures to Dart. These checks cannot
  guarantee recovery from every native PDF engine fault or OS process kill.

Review these changes when upgrading pdfx; do not replace this folder with a new
upstream version without retaining or revalidating the fixes. Test large legacy
PDFs on Android, including repeated zoom, app background/resume and closing
during a render. The compilation and automated app regressions do not substitute
for a device test with a user's failing PDF.
