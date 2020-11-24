from http.server import HTTPServer, BaseHTTPRequestHandler
import urllib
import os
import sys

fileFilter = lambda x: ".git" not in x

cached_paths = {}
    
class UpdateHTTPRequestHandler(BaseHTTPRequestHandler):
    def filesModTime(self, path='.'):
        oswalk = list(os.walk(path))
        directories = list(filter(fileFilter, [dir for dirlist in ([root+'\\'+dir for dir in dirs] for root, dirs, files in oswalk) for dir in dirlist]))
        files = list(filter(fileFilter, [file for filelist in ([root+'\\'+file for file in files] for root, dirs, files in oswalk) for file in filelist]))
        return {**{os.path.relpath(full_path, path): {'mtime': os.path.getmtime(full_path), 'isdir': True} for full_path in directories}, 
                **{os.path.relpath(full_path, path): {'mtime': os.path.getmtime(full_path), 'isdir': False} for full_path in files}}
    
    def do_GET(self):
        try:
            try:
                path, args = self.path.split('?',1)
                args = {x.split('=')[0]: x.split('=')[1] for x in args.split('&')}
            except ValueError:  # no args
                self.serve_path(self.path)
            except IndexError:  # malformed request (missing =value or k=v list after ?)
                self.send_error(400, explain="Malformed request, check your query parameters")
            else:
                self.serve_path(path, args)
        except:
            self.send_error(500)
            raise

    def serve_path(self, path, args=None):
        if path == '/heartbeat':
            self.serve_heartbeat(args)
        elif path.startswith('/file/') or path == '/file':
            self.serve_file(path, args)
        elif path == '/':
            self.serve_root(args)
        elif path == '/favicon.ico':
            self.serve_favicon()
        else:
            self.send_error(404, "Invalid resource path") 

    def serve_heartbeat(self, args):
        global cached_paths
        new_cached_paths = self.filesModTime(sys.argv[1])
        deleted = {k.replace("\\", "/"):v for k,v in cached_paths.items() if k not in new_cached_paths}
        created = {k.replace("\\", "/"):v for k,v in new_cached_paths.items() if k not in cached_paths}
        modified = {k.replace("\\", "/"):v for k,v in cached_paths.items() if k in new_cached_paths and v != new_cached_paths[k]}
        cached_paths = new_cached_paths
        
        if deleted or created or modified:
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            for filename, meta in modified.items():
                if meta['isdir'] == False:
                    self.wfile.write(bytes("update "+filename+" "+str(meta['isdir'])+"\n", "utf8"))
            for filename, meta in created.items():
                self.wfile.write(bytes("create "+filename+" "+str(meta['isdir'])+"\n", "utf8"))
            for filename, meta in deleted.items():
                self.wfile.write(bytes("delete "+filename+" "+str(meta['isdir'])+"\n", "utf8"))
        else:
            self.send_response(304, "No files modified")
            self.end_headers()

    def serve_file(self, path, args):
        try:
            filepath = os.path.join(sys.argv[1], urllib.parse.unquote_plus(path.split('/file/')[1]))
            file_handle = open(filepath, "rb")
            self.send_response(200)
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(file_handle.read())
            file_handle.close()
        except IndexError:
            self.send_error(400, explain="No file specified")
        except FileNotFoundError:
            self.send_error(404, explain="Requested file not found")
        except OSError as e:
            self.send_error(404, explain="Couldn't access file, reason: %s" % e.strerror)
        except PermissionError:
            self.send_error(400, explain="Cannot access folder as a file")

    def serve_root(self, args):
        self.send_response(200)
        self.send_header("Content-type", "text/html")
        self.end_headers()
        self.wfile.write(bytes("<html></head></head><body>Docs here</body></html>", "utf8"))
        
    def serve_favicon(self):
        favicon = open("favicon.ico", "rb")
        self.send_response(200)
        self.send_header("Content-type", "image/x-icon")
        self.end_headers()
        self.wfile.write(bytes(favicon.read()))
        favicon.close()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        if os.path.exists(sys.argv[1]) and os.path.isdir(sys.argv[1]):
            server = HTTPServer(('', 8000), UpdateHTTPRequestHandler)
            try:
                print("Starting server")
                server.serve_forever()
            except KeyboardInterrupt:
                print("Stopping Server")
                server.server_close()    
        else:
            print("Error: Provided path doesn't exist or isn't a directory")
    else:
        print("Usage: python webServerWatcher.py directory")
    