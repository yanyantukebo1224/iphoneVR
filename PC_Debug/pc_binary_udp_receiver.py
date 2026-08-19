import socket
import struct
import time

# C struct TrackingPacket と完全一致するバイナリフォーマット
# magic(I), sequence(I), timestamp(d), headPos(3f), headRot(4f), hands(2 x HandPacketData)
HEADER_FORMAT = "<II d 3f 4f"
HEADER_SIZE = struct.calcsize(HEADER_FORMAT)

# HandPacketData: chirality(B), isTracked(B), isPinching(B), pinchDistance(f), joints(21 x 7f)
HAND_FORMAT = "<BBB f " + "7f " * 21
HAND_SIZE = struct.calcsize(HAND_FORMAT)

PACKET_FORMAT = HEADER_FORMAT + HAND_FORMAT[1:] + HAND_FORMAT[1:]

def run_udp_receiver(port=9050):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", port))
    print(f"[*] iPhoneVR Binary UDP Receiver listening on port {port}...")

    last_time = time.time()
    count = 0

    while True:
        data, addr = sock.recvfrom(2048)
        if len(data) >= 8:
            magic, seq = struct.unpack("<II", data[:8])
            if magic == 0x52565049: # "IPVR"
                count += 1
                now = time.time()
                if now - last_time >= 1.0:
                    print(f"[{time.strftime('%H:%M:%S')}] Received {count} packets/sec from {addr[0]} (Seq: {seq})")
                    count = 0
                    last_time = now

if __name__ == "__main__":
    run_udp_receiver()
