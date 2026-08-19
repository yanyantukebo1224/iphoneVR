#include "udp_receiver.h"
#include <iostream>
#include <cstring>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")
typedef int socklen_t;
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#define SOCKET int
#define INVALID_SOCKET -1
#define SOCKET_ERROR -1
#define closesocket close
#endif

UDPReceiver::UDPReceiver() : m_port(9050), m_running(false) {}

UDPReceiver::~UDPReceiver() {
    Stop();
}

bool UDPReceiver::Start(uint16_t port, PacketCallback callback) {
    m_port = port;
    m_callback = callback;
    m_running = true;

    m_thread = std::thread(&UDPReceiver::ReceiveLoop, this);
    return true;
}

void UDPReceiver::Stop() {
    if (m_running) {
        m_running = false;
        if (m_thread.joinable()) {
            m_thread.join();
        }
    }
}

void UDPReceiver::ReceiveLoop() {
#ifdef _WIN32
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        return;
    }
#endif

    SOCKET sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock == INVALID_SOCKET) {
#ifdef _WIN32
        WSACleanup();
#endif
        return;
    }

    sockaddr_in serverAddr{};
    serverAddr.sin_family = AF_INET;
    serverAddr.sin_addr.s_addr = INADDR_ANY;
    serverAddr.sin_port = htons(m_port);

    if (bind(sock, (struct sockaddr*)&serverAddr, sizeof(serverAddr)) == SOCKET_ERROR) {
        closesocket(sock);
#ifdef _WIN32
        WSACleanup();
#endif
        return;
    }

    uint8_t buffer[2048];

    while (m_running) {
        sockaddr_in clientAddr{};
        socklen_t clientAddrLen = sizeof(clientAddr);

        int bytesReceived = recvfrom(sock, (char*)buffer, sizeof(buffer), 0, (struct sockaddr*)&clientAddr, &clientAddrLen);
        if (bytesReceived >= sizeof(TrackingPacket)) {
            TrackingPacket packet;
            std::memcpy(&packet, buffer, sizeof(TrackingPacket));

            if (packet.magic == IPPHONE_VR_MAGIC) {
                if (m_callback) {
                    m_callback(packet);
                }
            }
        }
    }

    closesocket(sock);
#ifdef _WIN32
    WSACleanup();
#endif
}
