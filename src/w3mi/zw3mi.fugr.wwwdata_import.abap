FUNCTION wwwdata_import.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(KEY) LIKE  WWWDATATAB STRUCTURE  WWWDATATAB
*"  TABLES
*"      MIME STRUCTURE  W3MIME OPTIONAL
*"  EXCEPTIONS
*"      WRONG_OBJECT_TYPE
*"      IMPORT_ERROR
*"----------------------------------------------------------------------

  DATA filename TYPE string.
  DATA xstr     TYPE xstring.
  DATA row      TYPE w3mime.
  DATA len      TYPE i.
  DATA lv_error TYPE abap_bool.
  DATA off      TYPE i.
  DATA total    TYPE i.

  CLEAR mime.

  WRITE '@KERNEL const w3obj = abap.W3MI?.[key.get().objid.get().trimEnd()];'.
  WRITE '@KERNEL lv_error.set(w3obj === undefined ? "X" : " ");'.

  IF lv_error = abap_true.
    RAISE import_error.
  ENDIF.

  " Reuse w3obj directly
  WRITE '@KERNEL filename.set(w3obj.filename);'.

* Where the bytes come from is the host's business, not this function's.
*
* Reading the file beside the transpiled module is right when there is a
* file and a filesystem, which is Node on a checkout. It is wrong in a
* browser, where there is neither, and wrong in a compiled binary, where
* the module lives in a virtual root and the media never got carried in.
* Both of those can fetch or unpack the bytes perfectly well; they just
* cannot do it with fs. So a host may install abap.W3MI_LOADER and answer
* for itself, and the disk stays the fallback rather than the only way.
*
* The loader is given the object id and the file name and returns the
* content as upper-case hex, which is what an xstring is carried as here.
  WRITE '@KERNEL if (typeof abap.W3MI_LOADER === "function") {'.
  WRITE '@KERNEL   xstr.set(await abap.W3MI_LOADER(key.get().objid.get().trimEnd(), filename.get()));'.
  WRITE '@KERNEL } else {'.
  WRITE '@KERNEL   const fs = await import("fs");'.
  WRITE '@KERNEL   const path = await import("path");'.
  WRITE '@KERNEL   const url = await import("url");'.
  WRITE '@KERNEL   const __filename = url.fileURLToPath(import.meta.url);'.
  WRITE '@KERNEL   const __dirname = path.dirname(__filename);'.
  WRITE '@KERNEL   xstr.set(fs.readFileSync(__dirname + path.sep + filename.get()).toString("hex").toUpperCase());'.
  WRITE '@KERNEL }'.

* Walked with an offset rather than consumed from the front. Reassigning
* the remainder copies it every time, so a four megabyte object is sixteen
* thousand copies of an ever shorter string and the whole thing is
* quadratic: an image of a few kilobytes is instant and an audio file takes
* minutes, during which the process serving it answers nobody. Reading a
* slice at an offset copies only the slice.
  total = xstrlen( xstr ).
  WHILE off < total.
    len = 255.
    IF total - off < len.
      len = total - off.
    ENDIF.
    row-line = xstr+off(len).
    APPEND row TO mime.
    off = off + len.
  ENDWHILE.

* temp workaround, classic exceptions not really handled in transpiler yet
  sy-subrc = 0.

ENDFUNCTION.
