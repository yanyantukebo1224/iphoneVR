#include <winsock2.h>
#include <windows.h>
#include <ws2tcpip.h>
#include <gdiplus.h>
#include "screen_streamer.h"
#include <iostream>
#include <sstream>

#pragma comment(lib, "gdiplus.lib")
#pragma comment(lib, "ws2_32.lib")

using namespace Gdiplus;

static int GetEncoderClsid(const WCHAR* format, CLSID* pClsid) {
    UINT num = 0;
    UINT size = 0;
    GetImageEncodersSize(&num, &size);
    if (size == 0) return -1;

    ImageCodecInfo* pImageCodecInfo = (ImageCodecInfo*)(malloc(size));
    if (pImageCodecInfo == NULL) return -1;

    GetImageEncoders(num, size, pImageCodecInfo);
    for (UINT j = 0; j < num; ++j) {
        if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0) {
            *pClsid = pImageCodecInfo[j].Clsid;
            free(pImageCodecInfo);
            return j;
        }
    }
    free(pImageCodecInfo);
    return -1;
}

ScreenStreamer::ScreenStreamer() : m_running(false) {}

ScreenStreamer::~ScreenStreamer() {
    Stop();
}

bool ScreenStreamer::Start(int port) {
    if (m_running) return true;
    m_running = true;

    m_captureThread = std::thread(&ScreenStreamer::CaptureLoop, this);
    m_serverThread = std::thread(&ScreenStreamer::StreamServerLoop, this, port);
    return true;
}

void ScreenStreamer::Stop() {
    if (!m_running) return;
    m_running = false;

    if (m_captureThread.joinable()) m_captureThread.join();
    if (m_serverThread.joinable()) m_serverThread.join();
}

void ScreenStreamer::CaptureLoop() {
    GdiplusStartupInput gdiplusStartupInput;
    ULONG_PTR gdiplusToken;
    GdiplusStartup(&gdiplusToken, &gdiplusStartupInput, NULL);

    CLSID jpgClsid;
    GetEncoderClsid(L"image/jpeg", &jpgClsid);

    EncoderParameters encoderParams;
    encoderParams.Count = 1;
    encoderParams.Parameter[0].Guid = EncoderQuality;
    encoderParams.Parameter[0].Type = EncoderParameterValueTypeLong;
    encoderParams.Parameter[0].NumberOfValues = 1;
    ULONG quality = 60;
    encoderParams.Parameter[0].Value = &quality;

    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);

    // 🖥️ 720p 高速スケールバッファ (超軽量 30KB/frame 転送)
    int streamW = 1280;
    int streamH = 720;

    HDC hdcScreen = GetDC(NULL);
    HDC hdcMem = CreateCompatibleDC(hdcScreen);
    HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, screenW, screenH);
    HGDIOBJ hOldBitmap = SelectObject(hdcMem, hBitmap);

    HDC hdcScaled = CreateCompatibleDC(hdcScreen);
    HBITMAP hScaledBitmap = CreateCompatibleBitmap(hdcScreen, streamW, streamH);
    HGDIOBJ hOldScaled = SelectObject(hdcScaled, hScaledBitmap);
    SetStretchBltMode(hdcScaled, COLORONCOLOR);

    while (m_running) {
        auto startTime = std::chrono::steady_clock::now();

        auto targetHwnd = FindWindowA(NULL, "Headset Window");
        if (!targetHwnd) targetHwnd = FindWindowW(NULL, L"VRビュー");
        if (!targetHwnd) targetHwnd = FindWindowA(NULL, "VR View");
        if (!targetHwnd) targetHwnd = FindWindowA("ValveVRUnlitWindow", NULL);
        if (!targetHwnd) targetHwnd = FindWindowA("ValveVRScene", NULL);

        int captureX = 0;
        int captureY = 0;
        int captureW = screenW;
        int captureH = screenH;

        if (targetHwnd != NULL && IsWindow(targetHwnd)) {
            RECT rc;
            if (GetClientRect(targetHwnd, &rc)) {
                POINT pt = { 0, 0 };
                ClientToScreen(targetHwnd, &pt);
                int w = rc.right - rc.left;
                int h = rc.bottom - rc.top;
                if (w > 100 && h > 100) {
                    captureX = pt.x;
                    captureY = pt.y;
                    captureW = w;
                    captureH = h;
                }
            }
        }

        // 🖥️ Zero-Overhead Direct Desktop BitBlt Capture
        BitBlt(hdcMem, 0, 0, captureW, captureH, hdcScreen, captureX, captureY, SRCCOPY);

        // 🚀 高速縮小転送 (720p)
        StretchBlt(hdcScaled, 0, 0, streamW, streamH, hdcMem, 0, 0, captureW, captureH, SRCCOPY);

        Bitmap bitmap(hScaledBitmap, NULL);
        IStream* pStream = NULL;
        if (CreateStreamOnHGlobal(NULL, TRUE, &pStream) == S_OK) {
            if (bitmap.Save(pStream, &jpgClsid, &encoderParams) == Ok) {
                STATSTG stat;
                pStream->Stat(&stat, STATFLAG_NONAME);
                ULONG size = (ULONG)stat.cbSize.QuadPart;

                std::vector<uint8_t> buffer(size);
                LARGE_INTEGER liZero = { 0 };
                pStream->Seek(liZero, STREAM_SEEK_SET, NULL);
                ULONG read = 0;
                pStream->Read(buffer.data(), size, &read);

                {
                    std::lock_guard<std::mutex> lock(m_frameMutex);
                    m_latestJpegFrame = std::move(buffer);
                }
            }
            pStream->Release();
        }

        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - startTime).count();
        int sleepMs = (int)(16 - elapsed);
        if (sleepMs > 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(sleepMs));
        }
    }

    SelectObject(hdcScaled, hOldScaled);
    DeleteObject(hScaledBitmap);
    DeleteDC(hdcScaled);

    SelectObject(hdcMem, hOldBitmap);
    DeleteObject(hBitmap);
    DeleteDC(hdcMem);
    ReleaseDC(NULL, hdcScreen);

    GdiplusShutdown(gdiplusToken);
}

void ScreenStreamer::StreamServerLoop(int port) {
    SOCKET listenSock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listenSock == INVALID_SOCKET) return;

    BOOL opt = TRUE;
    setsockopt(listenSock, SOL_SOCKET, SO_REUSEADDR, (const char*)&opt, sizeof(opt));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons((u_short)port);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(listenSock, (sockaddr*)&addr, sizeof(addr)) != 0) {
        closesocket(listenSock);
        return;
    }

    listen(listenSock, 8);

    while (m_running) {
        fd_set readSet;
        FD_ZERO(&readSet);
        FD_SET(listenSock, &readSet);

        timeval tv{ 0, 100000 };
        int sel = select(0, &readSet, NULL, NULL, &tv);
        if (sel > 0 && FD_ISSET(listenSock, &readSet)) {
            SOCKET clientSock = accept(listenSock, NULL, NULL);
            if (clientSock != INVALID_SOCKET) {
                std::thread([this, clientSock]() {
                    char reqBuf[1024] = { 0 };
                    int reqLen = recv(clientSock, reqBuf, sizeof(reqBuf) - 1, 0);
                    if (reqLen <= 0) {
                        closesocket(clientSock);
                        return;
                    }

                    std::string req(reqBuf);
                    if (req.find("/screen.jpg") != std::string::npos) {
                        // 単一 JPEG レスポンス
                        std::vector<uint8_t> frame;
                        {
                            std::lock_guard<std::mutex> lock(m_frameMutex);
                            frame = m_latestJpegFrame;
                        }
                        std::ostringstream ss;
                        ss << "HTTP/1.1 200 OK\r\n"
                           << "Content-Type: image/jpeg\r\n"
                           << "Content-Length: " << frame.size() << "\r\n"
                           << "Access-Control-Allow-Origin: *\r\n\r\n";
                        std::string resp = ss.str();
                        send(clientSock, resp.c_str(), (int)resp.size(), 0);
                        if (!frame.empty()) {
                            send(clientSock, (const char*)frame.data(), (int)frame.size(), 0);
                        }
                    } else {
                        // MJPEG Multipart リアルタイムストリーム
                        std::string header = 
                            "HTTP/1.1 200 OK\r\n"
                            "Content-Type: multipart/x-mixed-replace; boundary=--frame\r\n"
                            "Access-Control-Allow-Origin: *\r\n\r\n";
                        send(clientSock, header.c_str(), (int)header.size(), 0);

                        while (m_running) {
                            std::vector<uint8_t> frame;
                            {
                                std::lock_guard<std::mutex> lock(m_frameMutex);
                                frame = m_latestJpegFrame;
                            }

                            if (!frame.empty()) {
                                std::ostringstream ss;
                                ss << "--frame\r\n"
                                   << "Content-Type: image/jpeg\r\n"
                                   << "Content-Length: " << frame.size() << "\r\n\r\n";
                                std::string partHeader = ss.str();

                                if (send(clientSock, partHeader.c_str(), (int)partHeader.size(), 0) <= 0) break;
                                if (send(clientSock, (const char*)frame.data(), (int)frame.size(), 0) <= 0) break;
                                if (send(clientSock, "\r\n", 2, 0) <= 0) break;
                            }

                            std::this_thread::sleep_for(std::chrono::milliseconds(16));
                        }
                    }
                    closesocket(clientSock);
                }).detach();
            }
        }
    }

    closesocket(listenSock);
}