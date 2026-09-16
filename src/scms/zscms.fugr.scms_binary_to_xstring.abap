FUNCTION scms_binary_to_xstring.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(INPUT_LENGTH) TYPE  I
*"     VALUE(FIRST_LINE) TYPE  I DEFAULT 0
*"     VALUE(LAST_LINE) TYPE  I DEFAULT 0
*"  EXPORTING
*"     VALUE(BUFFER) TYPE  XSTRING
*"  TABLES
*"      BINARY_TAB
*"----------------------------------------------------------------------

* The rows of a binary table are fixed-width RAW, so the last one is padded
* and the true end of the content is INPUT_LENGTH rather than the table's
* own size. Concatenating and then cutting is the whole of it; cutting per
* row would need the row width, which the caller does not pass.

  DATA lv_all TYPE xstring.
  DATA ls_row TYPE w3mime.
  DATA lv_hex TYPE string.
  DATA lt_parts TYPE STANDARD TABLE OF string WITH EMPTY KEY.
  DATA lv_cut TYPE i.

  CLEAR buffer.

* An xstring is carried as hex here, so joining the rows is joining their
* hex and the bytes are exact. CONCATENATE IN BYTE MODE went through a
* character path and turned every byte above 0x7F into the UTF-8
* replacement, which reaches a browser as a PNG that is almost right: the
* worst kind of wrong, because the size and the content type still look
* plausible.
* Collected and joined once rather than concatenated in the loop. Appending
* to a string copies everything accumulated so far, so a four megabyte file
* is sixteen thousand copies of an ever longer string, and the listener
* serving it stops answering anybody at all for minutes. Linear instead.
  LOOP AT binary_tab INTO ls_row.
    APPEND ls_row-line TO lt_parts.
  ENDLOOP.
  CONCATENATE LINES OF lt_parts INTO lv_hex.

* a row is fixed width, so the last one is padded and INPUT_LENGTH is where
* the content actually ends. Two hex characters to the byte.
  lv_cut = input_length * 2.
  WRITE '@KERNEL if (lv_cut.get() > 0 && lv_cut.get() < lv_hex.get().length) { lv_hex.set(lv_hex.get().substring(0, lv_cut.get())); }'.

  WRITE '@KERNEL lv_all.set(lv_hex.get());'.
  buffer = lv_all.

ENDFUNCTION.
