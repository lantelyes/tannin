/* Tiny Direct3D 12 check for a Tannin runner: creates a device and prints what it finds.
 * Build: x86_64-w64-mingw32-gcc d3d12smoke.c -o d3d12smoke.exe -ld3d12 -ldxgi -ldxguid -luuid
 * It draws nothing. It only answers: does Direct3D 12 start, on which adapter, with what features. */
#define COBJMACROS
#include <windows.h>
#include <stdio.h>
#include <d3d12.h>
#include <dxgi1_4.h>

int main(void) {
    IDXGIFactory4 *factory = NULL;
    HRESULT hr = CreateDXGIFactory1(&IID_IDXGIFactory4, (void **)&factory);
    printf("CreateDXGIFactory1: 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 1;

    IDXGIAdapter1 *adapter = NULL;
    if (SUCCEEDED(IDXGIFactory4_EnumAdapters1(factory, 0, &adapter))) {
        DXGI_ADAPTER_DESC1 desc;
        IDXGIAdapter1_GetDesc1(adapter, &desc);
        printf("Adapter: %ls (vendor 0x%04x, device 0x%04x, %llu MB)\n", desc.Description,
               desc.VendorId, desc.DeviceId, (unsigned long long)(desc.DedicatedVideoMemory >> 20));
    }

    ID3D12Device *device = NULL;
    hr = D3D12CreateDevice((IUnknown *)adapter, D3D_FEATURE_LEVEL_11_0, &IID_ID3D12Device, (void **)&device);
    printf("D3D12CreateDevice: 0x%08lx\n", (unsigned long)hr);
    if (FAILED(hr)) return 2;

    static const D3D_FEATURE_LEVEL levels[] = {
        (D3D_FEATURE_LEVEL)0xb000, (D3D_FEATURE_LEVEL)0xc000, (D3D_FEATURE_LEVEL)0xc100, (D3D_FEATURE_LEVEL)0xc200};
    D3D12_FEATURE_DATA_FEATURE_LEVELS fl = {4, levels, 0};
    hr = ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_FEATURE_LEVELS, &fl, sizeof(fl));
    printf("Max feature level: 0x%04x (hr 0x%08lx)\n", (unsigned)fl.MaxSupportedFeatureLevel, (unsigned long)hr);

    D3D12_FEATURE_DATA_D3D12_OPTIONS5 o5;
    ZeroMemory(&o5, sizeof(o5));
    hr = ID3D12Device_CheckFeatureSupport(device, D3D12_FEATURE_D3D12_OPTIONS5, &o5, sizeof(o5));
    printf("Raytracing tier: %d (hr 0x%08lx)\n", (int)o5.RaytracingTier, (unsigned long)hr);

    char path[MAX_PATH];
    GetModuleFileNameA(GetModuleHandleA("d3d12.dll"), path, sizeof(path));
    printf("d3d12.dll loaded from: %s\n", path);
    fflush(stdout);
    return 0;
}
