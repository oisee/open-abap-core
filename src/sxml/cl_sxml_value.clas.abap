CLASS cl_sxml_value DEFINITION PUBLIC FINAL.
  PUBLIC SECTION.
    INTERFACES if_sxml_value_node.
    METHODS constructor IMPORTING value TYPE string.
  PRIVATE SECTION.
    DATA mv_value TYPE string.
ENDCLASS.

CLASS cl_sxml_value IMPLEMENTATION.
  METHOD constructor.
    if_sxml_node~type = if_sxml_node=>co_nt_value.
    mv_value = value.
  ENDMETHOD.

  METHOD if_sxml_value_node~get_value_raw.
    ASSERT 1 = 'todo'.
  ENDMETHOD.

  METHOD if_sxml_value_node~set_value.
    ASSERT 1 = 'todo'.
  ENDMETHOD.

  METHOD if_sxml_value_node~set_value_raw.
    ASSERT 1 = 'todo'.
  ENDMETHOD.

  METHOD if_sxml_value_node~get_value.
    value = mv_value.
  ENDMETHOD.
ENDCLASS.
