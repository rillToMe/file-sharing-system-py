import os
import urllib.parse
import tempfile
import zipfile
from http.server import SimpleHTTPRequestHandler, HTTPServer
import mimetypes

# Set directory uploads
UPLOADS_DIR = "D:/GrokVersion/uploads".replace("\\", "/")
print(f"Upload directory set to: {UPLOADS_DIR}") 

class CustomHTTPRequestHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        path = parsed_path.path
        print(f"Request path: {path}")  # Debug

        if path.lower().startswith('/uploads/'):
            file_name = urllib.parse.unquote(path[len('/uploads/'):].lstrip('/'))  # Decode URL
            file_path = os.path.join(UPLOADS_DIR, file_name)
            print(f"Resolved file path: {file_path}")  # Debug
            print(f"Checking existence of: {os.path.normpath(file_path)}")  # Debug path normalized
            if os.path.exists(file_path):
                try:
                    content_type, _ = mimetypes.guess_type(file_path)
                    print(f"File: {file_path}, MIME Type: {content_type}")  # Debug
                    if content_type is None:
                        content_type = 'application/octet-stream'
                        print(f"Defaulting MIME Type to: {content_type}")  # Debug
                    elif file_path.lower().endswith('.pdf'):
                        content_type = 'application/pdf'  # Force PDF MIME type
                        print(f"Forcing MIME Type to: {content_type} for PDF")

                    with open(file_path, 'rb') as file:
                        self.send_response(200)
                        self.send_header('Content-Disposition', f'attachment; filename="{os.path.basename(file_path)}"')
                        self.send_header('Content-Type', content_type)
                        self.end_headers()
                        while True:
                            chunk = file.read(8192)  # 8KB chunks
                            if not chunk:
                                break
                            try:
                                self.wfile.write(chunk)
                            except (ConnectionResetError, ConnectionAbortedError) as e:
                                print(f"Connection error during send: {e}")
                                break
                    print(f"Successfully sent file: {file_path} (Type: {content_type})")
                except PermissionError as e:
                    print(f"Permission denied: {e}")
                    self.send_response(403)
                    self.end_headers()
                    self.wfile.write(b'Permission denied')
                except Exception as e:
                    print(f"Error sending file: {e}")
                    self.send_response(500)
                    self.end_headers()
                    self.wfile.write(b'Internal server error')
            else:
                print(f"File not found: {file_path}. Listing directory contents: {os.listdir(UPLOADS_DIR)}")  # Debug file list
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b'File not found')
        elif path.lower().startswith('/download_folder/'):
            folder_name = urllib.parse.unquote(path[len('/download_folder/'):].lstrip('/'))  # Decode URL
            folder_path = os.path.join(UPLOADS_DIR, folder_name)
            print(f"Attempting to zip folder: {folder_path}")  # Debug
            if os.path.exists(folder_path) and os.path.isdir(folder_path):
                try:
                    with tempfile.NamedTemporaryFile(delete=False, suffix='.zip') as temp_zip:
                        with zipfile.ZipFile(temp_zip.name, 'w', zipfile.ZIP_DEFLATED) as zipf:
                            for root, _, files in os.walk(folder_path):
                                for file in files:
                                    file_path = os.path.join(root, file)
                                    arcname = os.path.relpath(file_path, folder_path)
                                    zipf.write(file_path, arcname)
                        temp_zip.seek(0)
                        self.send_response(200)
                        self.send_header('Content-Disposition', f'attachment; filename="{folder_name}.zip"')
                        self.send_header('Content-Type', 'application/zip')
                        self.send_header('Content-Length', str(os.path.getsize(temp_zip.name)))
                        self.end_headers()
                        self.wfile.write(temp_zip.read())
                    os.unlink(temp_zip.name)
                    print(f"Successfully sent folder as zip: {folder_name}.zip")
                except Exception as e:
                    print(f"Error zipping folder: {e}")
                    self.send_response(500)
                    self.end_headers()
                    self.wfile.write(b'Internal server error')
            else:
                print(f"Folder not found: {folder_path}. Checking UPLOADS_DIR: {UPLOADS_DIR}")  # Debug
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b'Folder not found')
        else:
            super().do_GET()
# Jalankan server
PORT = 8888
httpd = HTTPServer(('', PORT), CustomHTTPRequestHandler)
print(f"Serving at port {PORT}")
httpd.serve_forever()