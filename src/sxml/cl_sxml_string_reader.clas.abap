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
    cl_abap_conv_in_ce=>create( encoding = 'UTF-8' )->convert(
      EXPORTING input = input
      IMPORTING data  = decoded ).
    CREATE OBJECT reader TYPE lcl_reader
      EXPORTING
        iv_json = decoded.
  ENDMETHOD.
ENDCLASS.
