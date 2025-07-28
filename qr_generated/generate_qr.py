import qrcode
import socket

# Dapetin IP lokal
ip = socket.gethostbyname(socket.gethostname())
port = 8888
url = f"http://{ip}:{port}"

# Buat QR code
img = qrcode.make(url)
img.show()
