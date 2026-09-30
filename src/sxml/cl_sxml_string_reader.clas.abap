CLASS cl_sxml_string_reader DEFINITION PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS create
      IMPORTING
        input         TYPE xstring
      RETURNING
        VALUE(reader) TYPE REF TO if_sxml_reader.
ENDCLASS.

CLASS cl_sxml_string_reader IMPLEMENTATION.
  METHOD create.
    DATA decoded TYPE string.
    DATA bytes TYPE xstring.
    DATA encoding TYPE string VALUE 'UTF-8'.
    DATA sample TYPE string.
    DATA sample_length TYPE i.
    DATA sample_bytes TYPE xstring.
    bytes = input.
    IF xstrlen( bytes ) >= 3 AND bytes(3) = 'EFBBBF'.
      bytes = bytes+3.
    ELSEIF xstrlen( bytes ) >= 2 AND bytes(2) = 'FFFE'.
      bytes = bytes+2.
      encoding = 'UTF-16LE'.
    ELSEIF xstrlen( bytes ) >= 2 AND bytes(2) = 'FEFF'.
      bytes = bytes+2.
      encoding = 'UTF-16BE'.
    ELSE.
      sample_length = xstrlen( bytes ).
      IF sample_length > 256.
        sample_length = 256.
      ENDIF.
      IF sample_length > 0.
        sample_bytes = bytes(sample_length).
        cl_abap_conv_in_ce=>create( encoding = 'ISO-8859-1' )->convert(
          EXPORTING input = sample_bytes
          IMPORTING data  = sample ).
        IF strlen( sample ) >= 5 AND sample(5) = '<?xml'.
          FIND REGEX `encoding[ ]*=[ ]*['"]([^'"]+)['"]`
            IN sample SUBMATCHES encoding.
          IF sy-subrc <> 0.
            encoding = 'UTF-8'.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
    cl_abap_conv_in_ce=>create( encoding = CONV #( encoding ) )->convert(
      EXPORTING input = bytes
      IMPORTING data  = decoded ).
    CREATE OBJECT reader TYPE lcl_reader
      EXPORTING
        iv_json = decoded.
  ENDMETHOD.
ENDCLASS.
