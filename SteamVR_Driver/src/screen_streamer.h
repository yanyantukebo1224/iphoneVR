#ifndef SCREEN_STREAMER_H
#define SCREEN_STREAMER_H

#include <thread>
#include <atomic>
#include <vector>
#include <mutex>

class ScreenStreamer {
public:
    ScreenStreamer();
    ~ScreenStreamer();

    bool Start(int port = 9051);
    void Stop();

private:
    void StreamServerLoop(int port);
    void CaptureLoop();

    std::atomic<bool> m_running;
    std::thread m_serverThread;
    std::thread m_captureThread;

    std::mutex m_frameMutex;
    std::vector<uint8_t> m_latestJpegFrame;
};

#endif // SCREEN_STREAMER_H