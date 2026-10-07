CLASS ltcl_async_client DEFINITION FOR TESTING RISK LEVEL HARMLESS DURATION SHORT FINAL.
  PRIVATE SECTION.
    DATA mv_url TYPE string.
    DATA mt_clients TYPE STANDARD TABLE OF REF TO if_http_client WITH DEFAULT KEY.
    METHODS setup.
    METHODS teardown.
    METHODS make_client IMPORTING path TYPE string RETURNING VALUE(client) TYPE REF TO if_http_client.
    METHODS watch_failure.
    METHODS overlap FOR TESTING RAISING cx_static_check.
    METHODS refused_at_receive FOR TESTING RAISING cx_static_check.
    METHODS timeout_at_receive FOR TESTING RAISING cx_static_check.
    METHODS construction_at_send FOR TESTING RAISING cx_static_check.
    METHODS never_received FOR TESTING RAISING cx_static_check.
    METHODS receive_without_send FOR TESTING RAISING cx_static_check.
    METHODS reuse FOR TESTING RAISING cx_static_check.
    METHODS reset_at_receive FOR TESTING RAISING cx_static_check.
    METHODS invalid_timeout FOR TESTING RAISING cx_static_check.
    METHODS close_pending FOR TESTING RAISING cx_static_check.
ENDCLASS.

CLASS ltcl_async_client IMPLEMENTATION.
  METHOD setup.
    DATA url TYPE string.
    WRITE '@KERNEL const http = await import("node:http");'.
    WRITE '@KERNEL const zlib = await import("node:zlib");'.
    WRITE '@KERNEL this.unhandled = []; this.onUnhandled = error => this.unhandled.push(error);'.
    WRITE '@KERNEL process.on("unhandledRejection", this.onUnhandled);'.
    WRITE '@KERNEL this.waiting = []; this.peak = 0; this.timedOut = false; this.requests = 0;'.
    WRITE '@KERNEL this.arrived = new Promise(resolve => {this.signalArrived = resolve;});'.
    WRITE '@KERNEL this.release = () => {for (const [req, res] of this.waiting.splice(0)) {res.writeHead(200, {"x-request": req.url}); res.end(req.url);}};'.
    WRITE '@KERNEL this.server = http.createServer((req, res) => {this.requests++;'.
    WRITE '@KERNEL   if (req.url.startsWith("/delay")) {'.
    WRITE '@KERNEL     this.waiting.push([req, res]); this.peak = Math.max(this.peak, this.waiting.length);'.
    WRITE '@KERNEL     if (this.waiting.length === 3) this.signalArrived();'.
    WRITE '@KERNEL     if (this.timedOut) this.release(); return;'.
    WRITE '@KERNEL   }'.
    WRITE '@KERNEL   if (req.url === "/stall") {this.signalArrived(); return;}'.
    WRITE '@KERNEL   if (req.url === "/reset") {req.socket.destroy(); return;}'.
    WRITE '@KERNEL   if (req.url === "/gzip") {'.
    WRITE '@KERNEL     res.writeHead(201, "Created", {"content-encoding": "gzip", "content-type": "text/plain"});'.
    WRITE '@KERNEL     res.end(zlib.gzipSync(Buffer.from("compressed"))); return;'.
    WRITE '@KERNEL   }'.
    WRITE '@KERNEL   const chunks = []; req.on("data", chunk => chunks.push(chunk));'.
    WRITE '@KERNEL   req.on("end", () => {res.writeHead(200, {"x-seen": req.headers["x-snapshot"] || ""}); res.end(Buffer.concat(chunks));});'.
    WRITE '@KERNEL });'.
    WRITE '@KERNEL await new Promise(resolve => this.server.listen(0, "127.0.0.1", resolve));'.
    WRITE '@KERNEL url.set("http://127.0.0.1:" + this.server.address().port);'.
    mv_url = url.
    " Watchdog bounds a broken implementation; no assertion depends on elapsed time.
    WRITE '@KERNEL this.watchdog = setTimeout(() => {this.timedOut = true; this.signalArrived(); this.release(); this.server.closeAllConnections();}, 5000);'.
  ENDMETHOD.

  METHOD teardown.
    DATA client TYPE REF TO if_http_client.
    LOOP AT mt_clients INTO client.
      client->close( ).
    ENDLOOP.
    WRITE '@KERNEL clearTimeout(this.watchdog);'.
    WRITE '@KERNEL if (this.originalRequest) {'.
    WRITE '@KERNEL   (await import("node:http")).default.request = this.originalRequest;'.
    WRITE '@KERNEL   (await import("node:module")).syncBuiltinESMExports();'.
    WRITE '@KERNEL }'.
    WRITE '@KERNEL this.server.closeAllConnections();'.
    WRITE '@KERNEL await new Promise(resolve => this.server.close(resolve));'.
    " Advance the event loop out of the socket callback before subsequent tests.
    WRITE '@KERNEL await new Promise(resolve => setImmediate(resolve));'.
    WRITE '@KERNEL process.removeListener("unhandledRejection", this.onUnhandled);'.
  ENDMETHOD.

  METHOD make_client.
    cl_http_client=>create_by_url( EXPORTING url = mv_url && path IMPORTING client = client ).
    APPEND client TO mt_clients.
  ENDMETHOD.

  METHOD watch_failure.
    " Observe Node's actual request error, including failures before RECEIVE.
    WRITE '@KERNEL const http = (await import("node:http")).default;'.
    WRITE '@KERNEL this.originalRequest = http.request;'.
    WRITE '@KERNEL this.failed = new Promise(resolve => {'.
    WRITE '@KERNEL   http.request = (...args) => {'.
    WRITE '@KERNEL     const req = this.originalRequest(...args);'.
    WRITE '@KERNEL     req.once("error", error => queueMicrotask(() => resolve(error))); return req;'.
    WRITE '@KERNEL   };'.
    WRITE '@KERNEL });'.
    WRITE '@KERNEL (await import("node:module")).syncBuiltinESMExports();'.
  ENDMETHOD.

  METHOD overlap.
    DATA first TYPE REF TO if_http_client.
    DATA second TYPE REF TO if_http_client.
    DATA third TYPE REF TO if_http_client.
    DATA peak TYPE i.
    DATA expired TYPE abap_bool.
    first = make_client( '/delay1' ).
    second = make_client( '/delay2' ).
    third = make_client( '/delay3' ).
    first->send( ).
    second->send( ).
    third->send( ).
    WRITE '@KERNEL await this.arrived; peak.set(this.peak); expired.set(this.timedOut ? "X" : "");'.
    cl_abap_unit_assert=>assert_initial( first->response->get_data( ) ).
    WRITE '@KERNEL this.release();'.
    first->receive( ).
    second->receive( ).
    third->receive( ).
    cl_abap_unit_assert=>assert_initial( expired ).
    cl_abap_unit_assert=>assert_equals( act = peak
                                        exp = 3 ).
    cl_abap_unit_assert=>assert_equals( act = first->response->get_cdata( )
                                        exp = '/delay1' ).
    cl_abap_unit_assert=>assert_equals( act = second->response->get_cdata( )
                                        exp = '/delay2' ).
    cl_abap_unit_assert=>assert_equals( act = third->response->get_cdata( )
                                        exp = '/delay3' ).
    cl_abap_unit_assert=>assert_equals( act = third->response->get_header_field( 'x-request' )
                                        exp = '/delay3' ).
  ENDMETHOD.

  METHOD refused_at_receive.
    DATA client TYPE REF TO if_http_client.
    DATA code TYPE i.
    DATA message TYPE string.
    DATA path TYPE string.
    " Reserve and close a local listening port before attempting the connection.
    WRITE '@KERNEL const net = await import("node:net"); const reservation = net.createServer();'.
    WRITE '@KERNEL await new Promise(resolve => reservation.listen(0, "127.0.0.1", resolve));'.
    WRITE '@KERNEL path.set("http://127.0.0.1:" + reservation.address().port);'.
    WRITE '@KERNEL await new Promise(resolve => reservation.close(resolve));'.
    cl_http_client=>create_by_url( EXPORTING url = path IMPORTING client = client ).
    APPEND client TO mt_clients.
    watch_failure( ).
    client->send( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 0 ).
    WRITE '@KERNEL await this.failed;'.
    client->receive( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
    client->get_last_error( IMPORTING code = code message = message ).
    cl_abap_unit_assert=>assert_true( xsdbool( code <> 0 ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( message CS 'ECONNREFUSED' ) ).
    WRITE '@KERNEL console.log("refused: " + message.get());'.
  ENDMETHOD.

  METHOD timeout_at_receive.
    DATA client TYPE REF TO if_http_client.
    DATA code TYPE i.
    DATA message TYPE string.
    client = make_client( '/stall' ).
    watch_failure( ).
    client->send( EXPORTING timeout = 1 EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 0 ).
    WRITE '@KERNEL await this.arrived; await this.failed;'.
    client->receive( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
    client->get_last_error( IMPORTING code = code message = message ).
    cl_abap_unit_assert=>assert_equals( act = code
                                        exp = 402 ).
    cl_abap_unit_assert=>assert_true( xsdbool( message CS 'timed out after 1s' ) ).
    WRITE '@KERNEL console.log("timeout: " + message.get());'.
  ENDMETHOD.

  METHOD construction_at_send.
    DATA client TYPE REF TO if_http_client.
    DATA code TYPE i.
    DATA message TYPE string.
    client = make_client( '/echo' ).
    client->request->set_header_field( name  = 'x-bad'
                                       value = |a{ cl_abap_char_utilities=>newline }b| ).
    client->send( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
    client->get_last_error( IMPORTING code = code message = message ).
    cl_abap_unit_assert=>assert_true( xsdbool( code <> 0 ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( message CS 'Invalid character' ) ).
    client->receive( EXCEPTIONS http_invalid_state = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
  ENDMETHOD.

  METHOD never_received.
    DATA client TYPE REF TO if_http_client.
    DATA count TYPE i.
    client = make_client( '/reset' ).
    watch_failure( ).
    client->send( ).
    WRITE '@KERNEL await this.failed;'.
    " Two event-loop turns allow Node to report any unhandled rejection.
    WRITE '@KERNEL await new Promise(resolve => setImmediate(resolve));'.
    WRITE '@KERNEL await new Promise(resolve => setImmediate(resolve));'.
    WRITE '@KERNEL count.set(this.unhandled.length);'.
    client->close( ).
    cl_abap_unit_assert=>assert_equals( act = count
                                        exp = 0 ).
  ENDMETHOD.

  METHOD receive_without_send.
    DATA client TYPE REF TO if_http_client.
    client = make_client( '/echo' ).
    client->receive( EXCEPTIONS http_invalid_state = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
  ENDMETHOD.

  METHOD reuse.
    DATA client TYPE REF TO if_http_client.
    DATA code TYPE i.
    DATA message TYPE string.
    client = make_client( '/gzip' ).
    client->send( ).
    cl_abap_unit_assert=>assert_initial( client->response->get_data( ) ).
    client->receive( ).
    cl_abap_unit_assert=>assert_equals( act = client->response->get_cdata( )
                                        exp = 'compressed' ).
    cl_abap_unit_assert=>assert_equals( act = client->response->get_header_field( '~status_code' )
                                        exp = '201' ).
    cl_abap_unit_assert=>assert_equals( act = client->response->get_header_field( '~status_reason' )
                                        exp = 'Created' ).
    cl_abap_unit_assert=>assert_equals( act = client->response->get_header_field( '~server_protocol' )
                                        exp = 'HTTP/1.1' ).
    client->request->set_header_field( name  = '~request_uri'
                                       value = '/reset' ).
    client->send( ).
    client->receive( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
    client->get_last_error( IMPORTING code = code message = message ).
    cl_abap_unit_assert=>assert_true( xsdbool( code <> 0 AND code <> 201 ) ).
    cl_abap_unit_assert=>assert_true( xsdbool( message CS 'socket hang up' ) ).
    client->response->get_status( IMPORTING code = code ).
    cl_abap_unit_assert=>assert_equals( act = code
                                        exp = 0 ).
    cl_abap_unit_assert=>assert_initial( client->response->get_data( ) ).
    client->request->set_header_field( name  = '~request_uri'
                                       value = '/echo' ).
    client->request->set_method( 'POST' ).
    client->request->set_data( 'C3A9FF00' ).
    client->request->set_header_field( name  = 'x-snapshot'
                                       value = 'sent' ).
    client->send( ).
    client->request->set_header_field( name  = 'x-snapshot'
                                       value = 'later' ).
    client->send( EXCEPTIONS http_invalid_state = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
    client->receive( ).
    cl_abap_unit_assert=>assert_equals( act = client->response->get_data( )
                                        exp = 'C3A9FF00' ).
    cl_abap_unit_assert=>assert_equals( act = client->response->get_header_field( 'x-seen' )
                                        exp = 'sent' ).
    cl_abap_unit_assert=>assert_initial( client->response->get_header_field( 'content-encoding' ) ).
    client->get_last_error( IMPORTING code = code message = message ).
    cl_abap_unit_assert=>assert_equals( act = code
                                        exp = 200 ).
    cl_abap_unit_assert=>assert_equals( act = message
                                        exp = 'todo_open_abap' ).
    client->receive( EXCEPTIONS http_invalid_state = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
  ENDMETHOD.

  METHOD reset_at_receive.
    DATA client TYPE REF TO if_http_client.
    client = make_client( '/reset' ).
    client->send( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 0 ).
    client->receive( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
  ENDMETHOD.

  METHOD invalid_timeout.
    DATA client TYPE REF TO if_http_client.
    DATA code TYPE i.
    DATA message TYPE string.
    DATA requests TYPE i.
    client = make_client( '/echo' ).
    client->send( EXPORTING timeout = -5 EXCEPTIONS http_invalid_timeout = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
    client->get_last_error( IMPORTING code = code ).
    cl_abap_unit_assert=>assert_equals( act = code
                                        exp = 17 ).
    client->receive( EXCEPTIONS http_communication_failure = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
    client->get_last_error( IMPORTING code = code message = message ).
    cl_abap_unit_assert=>assert_equals( act = code
                                        exp = 17 ).
    cl_abap_unit_assert=>assert_equals(
      act = message
      exp = 'Internal error. Handle for this http session was not found or is NULL.' ).
    cl_abap_unit_assert=>assert_initial( client->response->get_data( ) ).
    client->response->get_status( IMPORTING code = code ).
    cl_abap_unit_assert=>assert_equals( act = code
                                        exp = 0 ).
    WRITE '@KERNEL requests.set(this.requests);'.
    cl_abap_unit_assert=>assert_equals( act = requests
                                        exp = 0 ).
    client->close( ).
    client->send( ).
    client->receive( ).
    client->get_last_error( IMPORTING code = code ).
    cl_abap_unit_assert=>assert_equals( act = code
                                        exp = 200 ).
  ENDMETHOD.

  METHOD close_pending.
    DATA client TYPE REF TO if_http_client.
    client = make_client( '/stall' ).
    watch_failure( ).
    client->send( ).
    WRITE '@KERNEL await this.arrived;'.
    client->close( ).
    WRITE '@KERNEL await this.failed;'.
    client->receive( EXCEPTIONS http_invalid_state = 1 OTHERS = 2 ).
    cl_abap_unit_assert=>assert_subrc( exp = 1 ).
  ENDMETHOD.
ENDCLASS.
