"""断点续传专项测试：模拟"传到一半被掐断"的真实链路，验证 fetch 能续完。

背景：构建机出口链路经常在传大文件时卡死。若下载器不会续传，
GTK 这一百多个包的依赖链永远走不完（每次失败都从头丢几十 MB）。
这个测试用一个会按 Range 返回 206、并故意在首次请求掐断的本地
HTTP 服务复现该场景。
"""
import sys, os, tempfile, hashlib, threading, http.server
sys.path.insert(0, str(__import__('pathlib').Path(__file__).resolve().parents[1]))
from pathlib import Path
from qyos import util

DATA = os.urandom(300_000)
SHA = hashlib.sha256(DATA).hexdigest()

STATE = {"cut_once": True}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        rng = self.headers.get("Range")
        start = 0
        if rng:
            start = int(rng.split("=")[1].split("-")[0])
        chunk = DATA[start:]
        self.send_response(206 if rng else 200)
        if rng:
            self.send_header("Content-Range",
                             f"bytes {start}-{len(DATA)-1}/{len(DATA)}")
        self.send_header("Content-Length", str(len(chunk)))
        self.end_headers()
        # 第一次请求只发一半就掐断，模拟出口链路卡死
        if STATE["cut_once"]:
            STATE["cut_once"] = False
            self.wfile.write(chunk[: len(chunk) // 2])
            self.wfile.flush()
            self.close_connection = True
            return
        self.wfile.write(chunk)

    def log_message(self, *a):
        pass


def main() -> int:
    srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    port = srv.server_address[1]
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    d = Path(tempfile.mkdtemp(prefix="qy-resume-"))
    got = util.fetch(f"http://127.0.0.1:{port}/blob.bin", d, expected=SHA)

    ok_sha = util.sha256_file(got) == SHA
    ok_size = got.stat().st_size == len(DATA)
    print(f"  续传后 sha256 匹配: {ok_sha}")
    print(f"  续传后大小正确: {ok_size} ({got.stat().st_size} 字节)")
    if ok_sha and ok_size:
        print("[PASS] 断点续传在'首传被掐断'场景下完成下载")
        return 0
    print("[FAIL] 断点续传结果不正确")
    return 1


if __name__ == "__main__":
    sys.exit(main())
