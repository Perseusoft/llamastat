//! Memory, GPU and per-process stats. Memory/processes go through `sysinfo` on every OS;
//! GPU is per platform: IOKit on Apple Silicon, NVML for NVIDIA, sysfs for AMD on Linux.

use std::ffi::OsStr;

use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, RefreshKind, System, UpdateKind};

use crate::model::{GpuSnapshot, MemorySnapshot, ProcessMatch};

pub struct SystemStats {
    sys: System,
}

pub struct ProcessSample {
    pub ram: u64,
    /// Fraction of one core since the previous refresh.
    pub cpu: f64,
}

impl SystemStats {
    pub fn new() -> Self {
        Self { sys: System::new_with_specifics(RefreshKind::nothing()) }
    }

    pub fn memory(&mut self) -> MemorySnapshot {
        self.sys.refresh_memory();
        MemorySnapshot {
            total: self.sys.total_memory(),
            used: self.sys.used_memory(),
            swap_used: self.sys.used_swap(),
            swap_total: self.sys.total_swap(),
        }
    }

    /// Refreshes the process table (argv + memory + CPU). Call once per tick before `find`.
    pub fn refresh_processes(&mut self) {
        self.sys.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing().with_memory().with_cpu().with_cmd(UpdateKind::OnlyIfNotSet),
        );
    }

    pub fn find(&self, matcher: &ProcessMatch) -> Option<ProcessSample> {
        let (exe, matches): (&str, Box<dyn Fn(&[std::ffi::OsString]) -> bool>) = match matcher {
            ProcessMatch::FlagValue { exe, flag, value } => (exe, Box::new(move |args| {
                args.windows(2).any(|w| w[0] == OsStr::new(flag) && w[1] == OsStr::new(value.as_str()))
            })),
            ProcessMatch::ArgContains { exe, needle } => (exe, Box::new(move |args| {
                args.iter().any(|a| a.to_string_lossy().replace('\\', "/").contains(needle))
            })),
        };
        let (_, process) = self.sys.processes().iter().find(|(_, p)| {
            let name = p.name().to_string_lossy();
            (name == exe || name == format!("{exe}.exe")) && matches(p.cmd())
        })?;
        Some(ProcessSample { ram: process.memory(), cpu: process.cpu_usage() as f64 / 100.0 })
    }

    /// Value following `--flag` in the argv of the first `exe` process (e.g. the router's `--models-preset`).
    pub fn flag_value(&self, exe: &str, flag: &str) -> Option<String> {
        self.sys.processes().values().find_map(|p| {
            let name = p.name().to_string_lossy();
            if name != exe && name != format!("{exe}.exe") { return None; }
            p.cmd().windows(2).find(|w| w[0] == OsStr::new(flag)).map(|w| w[1].to_string_lossy().into_owned())
        })
    }

    #[allow(dead_code)]
    pub fn process(&self, pid: u32) -> Option<ProcessSample> {
        let p = self.sys.process(Pid::from_u32(pid))?;
        Some(ProcessSample { ram: p.memory(), cpu: p.cpu_usage() as f64 / 100.0 })
    }

    pub fn gpu(&self) -> Option<GpuSnapshot> {
        gpu::read()
    }
}

#[cfg(target_os = "macos")]
mod gpu {
    use core_foundation::base::{kCFAllocatorDefault, CFType, TCFType};
    use core_foundation::dictionary::{CFDictionary, CFMutableDictionaryRef};
    use core_foundation::number::CFNumber;
    use core_foundation::string::CFString;
    use io_kit_sys::types::io_iterator_t;
    use io_kit_sys::*;

    use crate::model::GpuSnapshot;

    /// Apple Silicon GPU's PerformanceStatistics from the IORegistry (no root needed).
    pub fn read() -> Option<GpuSnapshot> {
        unsafe {
            let matching = IOServiceMatching(c"IOAccelerator".as_ptr());
            let mut iterator: io_iterator_t = 0;
            #[allow(deprecated)]
            if IOServiceGetMatchingServices(kIOMasterPortDefault, matching as _, &mut iterator) != 0 {
                return None;
            }
            let mut result = None;
            loop {
                let service = IOIteratorNext(iterator);
                if service == 0 {
                    break;
                }
                let mut props: CFMutableDictionaryRef = std::ptr::null_mut();
                let ok = IORegistryEntryCreateCFProperties(service, &mut props, kCFAllocatorDefault, 0) == 0;
                IOObjectRelease(service);
                if !ok || props.is_null() {
                    continue;
                }
                let dict: CFDictionary<CFString, CFType> = CFDictionary::wrap_under_create_rule(props as _);
                let Some(perf) = dict.find(CFString::from_static_string("PerformanceStatistics"))
                    .and_then(|v| v.downcast::<CFDictionary>())
                else { continue };
                let perf: CFDictionary<CFString, CFType> = CFDictionary::wrap_under_get_rule(perf.as_concrete_TypeRef());
                let number = |key: &'static str| {
                    perf.find(CFString::from_static_string(key))
                        .and_then(|v| v.downcast::<CFNumber>())
                        .and_then(|n| n.to_i64())
                };
                if let Some(utilization) = number("Device Utilization %") {
                    result = Some(GpuSnapshot {
                        name: "Apple GPU".into(),
                        utilization: utilization as f64 / 100.0,
                        memory_used: number("In use system memory").map(|v| v as u64),
                        memory_total: None,
                    });
                    break;
                }
            }
            IOObjectRelease(iterator);
            result
        }
    }
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
mod gpu {
    use std::sync::OnceLock;

    use nvml_wrapper::Nvml;

    use crate::model::GpuSnapshot;

    /// NVML is loaded dynamically; machines without an NVIDIA driver just get None.
    fn nvml() -> Option<&'static Nvml> {
        static NVML: OnceLock<Option<Nvml>> = OnceLock::new();
        NVML.get_or_init(|| Nvml::init().ok()).as_ref()
    }

    pub fn read() -> Option<GpuSnapshot> {
        nvidia().or_else(amd)
    }

    fn nvidia() -> Option<GpuSnapshot> {
        let device = nvml()?.device_by_index(0).ok()?;
        let utilization = device.utilization_rates().ok()?;
        let memory = device.memory_info().ok();
        Some(GpuSnapshot {
            name: device.name().unwrap_or_else(|_| "NVIDIA GPU".into()),
            utilization: utilization.gpu as f64 / 100.0,
            memory_used: memory.as_ref().map(|m| m.used),
            memory_total: memory.as_ref().map(|m| m.total),
        })
    }

    /// amdgpu exposes busy % and VRAM in sysfs.
    #[cfg(target_os = "linux")]
    fn amd() -> Option<GpuSnapshot> {
        let read = |path: &std::path::Path| std::fs::read_to_string(path).ok()?.trim().parse::<u64>().ok();
        for entry in std::fs::read_dir("/sys/class/drm").ok()?.flatten() {
            let device = entry.path().join("device");
            if let Some(busy) = read(&device.join("gpu_busy_percent")) {
                return Some(GpuSnapshot {
                    name: "AMD GPU".into(),
                    utilization: busy as f64 / 100.0,
                    memory_used: read(&device.join("mem_info_vram_used")),
                    memory_total: read(&device.join("mem_info_vram_total")),
                });
            }
        }
        None
    }

    // TODO: Intel/AMD on Windows via PDH "GPU Engine" counters.
    #[cfg(target_os = "windows")]
    fn amd() -> Option<GpuSnapshot> {
        None
    }
}

#[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
mod gpu {
    pub fn read() -> Option<crate::model::GpuSnapshot> {
        None
    }
}
