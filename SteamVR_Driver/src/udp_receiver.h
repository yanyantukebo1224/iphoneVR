#ifndef UDP_RECEIVER_H
#define UDP_RECEIVER_H

#include "tracking_protocol.h"
#include <functional>
#include <atomic>
#include <thread>

typedef std::function<void(const TrackingPacket&)> PacketCallback;

class UDPReceiver {
public:
    UDPReceiver();
    ~UDPReceiver();

    bool Start(uint16_t port, PacketCallback callback);
    void Stop();

private:
    void ReceiveLoop();

    uint16_t m_port;
    PacketCallback m_callback;
    std::atomic<bool> m_running;
    std::thread m_thread;
};

#endif // UDP_RECEIVER_H
