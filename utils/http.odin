/*    
    http.odin
    An attempt to write my own http server.
    Implementation likely unsuitable for anything serious.
*/

package utils

import "core:fmt"
import "core:strings"
import "core:net"
import "core:os"

main :: proc() {
    port := 3000
    listen_and_serve(port)
}

listen_and_serve :: proc(port:= 3000) -> (err: net.Network_Error) {
    serve_dir, gwd_err := os.get_working_directory(context.allocator)
    if (gwd_err != nil) {
        fmt.println("soma (error): Failed to get working directory")
    }
    fmt.printfln("soma: Serving %q on http://localhost:%v\n", serve_dir, port)

    endpoint := net.Endpoint {
        address = net.IP4_Any,
        port = port,
    }

    listen_socket, listen_err := net.listen_tcp(endpoint)
    if (listen_err != nil) {
        fmt.printfln("Error creating listen_socket: %v", listen_err)
        return listen_err
    }

    defer net.close(listen_socket)

    // Listening loop
    for {
        client_socket, client_endpoint, accept_err := net.accept_tcp(listen_socket)
        if (accept_err != nil) {
            fmt.printfln("Error accepting client: %v", accept_err)
            continue
        }
        handle_http_client(client_socket, serve_dir)
    }

    return nil
}

handle_http_client :: proc(client_socket: net.TCP_Socket, serve_dir: string) {
    defer net.close(client_socket)
    defer free_all(context.temp_allocator)

    // Request
    buffer: [4096]u8

    bytes_read, rec_err := net.recv_tcp(client_socket, buffer[:])
    if (rec_err != nil) {
        fmt.printfln("Error receiving bytes: %v", rec_err)
        return
    }

    request_path, req_ok := _path_from_req(string(buffer[:bytes_read]))
    if (!req_ok) {
        _send_status_response(client_socket, "400 Bad Request")
        return
    }
    fmt.printfln("Request path: %s", request_path)

    // Response    
    file_path := _resolve_file_path(request_path, serve_dir)
    body, read_ok := _read_file_from_path(file_path)
    if (read_ok != nil) {
        _send_status_response(client_socket, "404 Not Found")
        return
    }
    
    content_type := _path_to_mime(file_path)
    cache_type := _cache_policy(file_path)

    headers := fmt.tprintf(
                "HTTP/1.1 200 OK\r\n" +
                "Content-Type: %s\r\n" +
                "Content-Length: %d\r\n" +
                "Cache-Control: %s\r\n" +
                "Connection: close\r\n" +
                "\r\n", content_type, len(body), cache_type)
    header_bytes := transmute([]byte)headers

    full_response := make([]byte, len(header_bytes) + len(body))
    defer delete(full_response)    

    copy(full_response[:len(header_bytes)], header_bytes)
    copy(full_response[len(header_bytes):], body)

    response, send_err := net.send_tcp(client_socket, full_response)
    if (send_err != nil) {
        fmt.printfln("Error sending tcp: %v", send_err)
    }
    fmt.printfln("Success: sent %i bytes\n", response)
}

_send_status_response :: proc(socket: net.TCP_Socket, status: string) -> () {
    response := fmt.tprintf(
        "HTTP/1.1 %s\r\n" +
        "Content-Type: text/plain\r\n" + 
        "Content-Length: %d\r\n" +
        "\r\n%s",
        status, len(status), status)
    _, err := net.send_tcp(socket, transmute([]byte)response)
    if (err != nil) {
        fmt.printfln("Error sending tcp: %v", err)
    }
}

_path_from_req :: proc(request: string) -> (path: string, ok: bool) {
    /* 
        GET / HTTP/1.1          ->  "/",        true
        GET /about/ HTTP/1.1    ->  "/about",   true 
        Malformed request       ->  "",         false
    */
    newline_index := strings.index(request, "\n")
    if (newline_index == -1) {
        return "", false
    }
    temp := request[:newline_index]

    req_header := strings.split(temp, " ", context.temp_allocator)
    if (len(req_header) != 3) {
        return "", false
    }

    return req_header[1], true
}

_resolve_file_path :: proc(request_path: string, serve_dir: string) -> string {
    /*  
        /               -> serve_dir/index.html
        /about          -> serve_dir/about/index.html
        /about/         -> serve_dir/about/index.html
        /favicon.ico    -> serve_dir/favicon.ico
    */
    path := request_path

    if (!strings.contains(path, ".")) {
        path = strings.trim_suffix(path, "/")
        path = strings.concatenate({path, "/index.html"}, context.temp_allocator)
    }

    final := strings.concatenate({serve_dir, path}, context.temp_allocator)
    fmt.printfln("Resolved file path: %s", final)
    fmt.printfln("extension return type: %s", _path_to_mime(final))
    return final
}

_path_to_mime :: proc(file_path: string) -> string {
    to_dot := strings.last_index(file_path, ".")
    if (to_dot == -1) {
        return "application/octet-stream"
    }
    file_ext := file_path[to_dot:]

    switch file_ext {
        case ".html":
            return "text/html"
        case ".css":
            return "text/css"
        case ".js":
            return "application/javascript"
        case ".png":
            return "image/png"
        case ".jpg", ".jpeg":
            return "image/jpeg"
        case ".webp":
            return "image/webp"
        case ".svg":
            return "image/svg+xml"
        case ".gif":
            return "image/gif"
        case ".ico":
            return "image/x-icon"
        case ".otf":
            return "font/otf"
        case ".ttf":
            return "font/ttf"
        case ".woff":
            return "font/woff"
        case ".woff2":
            return "font/woff2"
        case:
            return "application/octet-stream"
    }

    return "text/plain"
}

_cache_policy :: proc(file_path: string) -> (policy: string) {
    to_dot := strings.last_index(file_path, ".")
    if (to_dot == -1) {
        return "no-cache"
    }
    file_ext := file_path[to_dot:]

    // TODO: Implement `304 Not Modified`
    switch file_ext {
        case ".otf", ".ttf", ".woff", ".woff2":
            return "public, max-age=31536000, immutable"
        case ".js", ".css":
            return "public, max-age=0, must-revalidate"
        case:
            return "no-cache"
    }
}

_read_file_from_path :: proc(file_path: string) -> ([]byte, os.Error) {
    bytes_read, err := os.read_entire_file_from_path(file_path, context.temp_allocator)
    if (err != nil) {
        fmt.printfln("Error reading file: %s\n", file_path)
        return nil, nil
    }
    return bytes_read, err
}
