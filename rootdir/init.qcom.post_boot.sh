#!/system/bin/sh
# Copyright (c) 2012-2013, The Linux Foundation. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of The Linux Foundation nor
#       the names of its contributors may be used to endorse or promote
#       products derived from this software without specific prior written
#       permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON-INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
# OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
# OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
# ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

target=`getprop ro.board.platform`

function configure_memory_parameters() {
    # Set Memory paremeters.
    #
    # Set per_process_reclaim tuning parameters
    # 2GB 64-bit will have aggressive settings when compared to 1GB 32-bit
    # 1GB and less will use vmpressure range 50-70, 2GB will use 10-70
    # 1GB and less will use 512 pages swap size, 2GB will use 1024
    #
    # Set Low memory killer minfree parameters
    # 32 bit all memory configurations will use 15K series
    # 64 bit up to 2GB with use 14K, and above 2GB will use 18K
    #
    # Set ALMK parameters (usually above the highest minfree values)
    # 32 bit will have 53K & 64 bit will have 81K
    #
    # Set ZCache parameters
    # max_pool_percent is the percentage of memory that the compressed pool
    # can occupy.
    # clear_percent is the percentage of memory at which zcache starts
    # evicting compressed pages. This should be slighlty above adj0 value.
    # clear_percent = (adj0 * 100 / avalible memory in pages)+1
    #
    arch_type=`uname -m`
    MemTotalStr=`cat /proc/meminfo | grep MemTotal`
    MemTotal=${MemTotalStr:16:8}
    MemTotalPg=$((MemTotal / 4))
    adjZeroMinFree=18432
    echo 1 > /sys/module/process_reclaim/parameters/enable_process_reclaim
    echo 70 > /sys/module/process_reclaim/parameters/pressure_max
    echo 30 > /sys/module/process_reclaim/parameters/swap_opt_eff
    echo 1 > /sys/module/lowmemorykiller/parameters/enable_adaptive_lmk
    if [ "$arch_type" == "aarch64" ] && [ $MemTotal -gt 2097152 ]; then
        echo 10 > /sys/module/process_reclaim/parameters/pressure_min
        echo 1024 > /sys/module/process_reclaim/parameters/per_swap_size
        echo "18432,23040,27648,32256,55296,80640" > /sys/module/lowmemorykiller/parameters/minfree
        echo 81250 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
        adjZeroMinFree=18432
    elif [ "$arch_type" == "aarch64" ] && [ $MemTotal -gt 1048576 ]; then
        echo 10 > /sys/module/process_reclaim/parameters/pressure_min
        echo 1024 > /sys/module/process_reclaim/parameters/per_swap_size
        echo "14746,18432,22118,25805,40000,55000" > /sys/module/lowmemorykiller/parameters/minfree
        echo 81250 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
        adjZeroMinFree=14746
    elif [ "$arch_type" == "aarch64" ]; then
        echo 50 > /sys/module/process_reclaim/parameters/pressure_min
        echo 512 > /sys/module/process_reclaim/parameters/per_swap_size
        echo "14746,18432,22118,25805,40000,55000" > /sys/module/lowmemorykiller/parameters/minfree
        echo 81250 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
        adjZeroMinFree=14746
    else
        echo 50 > /sys/module/process_reclaim/parameters/pressure_min
        echo 512 > /sys/module/process_reclaim/parameters/per_swap_size
        echo "15360,19200,23040,26880,34415,43737" > /sys/module/lowmemorykiller/parameters/minfree
        echo 53059 > /sys/module/lowmemorykiller/parameters/vmpressure_file_min
        adjZeroMinFree=15360
    fi
    clearPercent=$((((adjZeroMinFree * 100) / MemTotalPg) + 1))
    echo $clearPercent > /sys/module/zcache/parameters/clear_percent
    echo 30 >  /sys/module/zcache/parameters/max_pool_percent

    # Zram disk - 512MB size
    zram_enable=`getprop ro.config.zram`
    if [ "$zram_enable" == "true" ]; then
        echo 536870912 > /sys/block/zram0/disksize
        mkswap /dev/block/zram0
        swapon /dev/block/zram0 -p 32758
    fi

    SWAP_ENABLE_THRESHOLD=1048576
    swap_enable=`getprop ro.config.swap`

    if [ -f /sys/devices/soc0/soc_id ]; then
        soc_id=`cat /sys/devices/soc0/soc_id`
    else
        soc_id=`cat /sys/devices/system/soc/soc0/id`
    fi

    # Enable swap initially only for 1 GB targets
    if [ "$MemTotal" -le "$SWAP_ENABLE_THRESHOLD" ] && [ "$swap_enable" == "true" ]; then
        # Static swiftness
        echo 1 > /proc/sys/vm/swap_ratio_enable
        echo 70 > /proc/sys/vm/swap_ratio

        # Swap disk - 200MB size
        if [ ! -f /data/system/swap/swapfile ]; then
            dd if=/dev/zero of=/data/system/swap/swapfile bs=1m count=200
        fi
        mkswap /data/system/swap/swapfile
        swapon /data/system/swap/swapfile -p 32758
    fi
}


case "$target" in
    "msm8953")

        if [ -f /sys/devices/soc0/soc_id ]; then
            soc_id=`cat /sys/devices/soc0/soc_id`
        else
            soc_id=`cat /sys/devices/system/soc/soc0/id`
        fi

        if [ -f /sys/devices/soc0/hw_platform ]; then
            hw_platform=`cat /sys/devices/soc0/hw_platform`
        else
            hw_platform=`cat /sys/devices/system/soc/soc0/hw_platform`
        fi

        case "$soc_id" in
            "293" | "304" )

                # Start Host based Touch processing
                case "$hw_platform" in
                     "MTP" | "Surf" | "RCM" )
                        #if this directory is present, it means that a
                        #1200p panel is connected to the device.
                        dir="/sys/bus/i2c/devices/3-0038"
                        if [ ! -d "$dir" ]; then
                              start hbtp
                        fi
                        ;;
                esac

                #scheduler settings
                echo 3 > /proc/sys/kernel/sched_window_stats_policy
                echo 3 > /proc/sys/kernel/sched_ravg_hist_size

                #task packing settings
                echo 0 > /sys/devices/system/cpu/cpu0/sched_static_cpu_pwr_cost
                echo 0 > /sys/devices/system/cpu/cpu1/sched_static_cpu_pwr_cost
                echo 0 > /sys/devices/system/cpu/cpu2/sched_static_cpu_pwr_cost
                echo 0 > /sys/devices/system/cpu/cpu3/sched_static_cpu_pwr_cost
                echo 0 > /sys/devices/system/cpu/cpu4/sched_static_cpu_pwr_cost
                echo 0 > /sys/devices/system/cpu/cpu5/sched_static_cpu_pwr_cost
                echo 0 > /sys/devices/system/cpu/cpu6/sched_static_cpu_pwr_cost
                echo 0 > /sys/devices/system/cpu/cpu7/sched_static_cpu_pwr_cost

                #init task load, restrict wakeups to preferred cluster
                echo 15 > /proc/sys/kernel/sched_init_task_load
                # spill load is set to 100% by default in the kernel
                echo 3 > /proc/sys/kernel/sched_spill_nr_run
                # Apply inter-cluster load balancer restrictions
                echo 1 > /proc/sys/kernel/sched_restrict_cluster_spill


                for devfreq_gov in /sys/class/devfreq/qcom,mincpubw*/governor
                do
                    echo "cpufreq" > $devfreq_gov
                done

                for devfreq_gov in /sys/class/devfreq/soc:qcom,cpubw/governor
                do
                    echo "bw_hwmon" > $devfreq_gov
                    for cpu_io_percent in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/io_percent
                    do
                        echo 34 > $cpu_io_percent
                    done
                    for cpu_guard_band in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/guard_band_mbps
                    do
                        echo 0 > $cpu_guard_band
                    done
                    for cpu_hist_memory in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/hist_memory
                    do
                        echo 20 > $cpu_hist_memory
                    done
                    for cpu_hyst_length in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/hyst_length
                    do
                        echo 10 > $cpu_hyst_length
                    done
                    for cpu_idle_mbps in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/idle_mbps
                    do
                        echo 1600 > $cpu_idle_mbps
                    done
                    for cpu_low_power_delay in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/low_power_delay
                    do
                        echo 20 > $cpu_low_power_delay
                    done
                    for cpu_low_power_io_percent in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/low_power_io_percent
                    do
                        echo 34 > $cpu_low_power_io_percent
                    done
                    for cpu_mbps_zones in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/mbps_zones
                    do
                        echo "1611 3221 5859 6445 7104" > $cpu_mbps_zones
                    done
                    for cpu_sample_ms in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/sample_ms
                    do
                        echo 4 > $cpu_sample_ms
                    done
                    for cpu_up_scale in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/up_scale
                    do
                        echo 250 > $cpu_up_scale
                    done
                    for cpu_min_freq in /sys/class/devfreq/soc:qcom,cpubw/min_freq
                    do
                        echo 1611 > $cpu_min_freq
                    done
                done

                for gpu_bimc_io_percent in /sys/class/devfreq/soc:qcom,gpubw/bw_hwmon/io_percent
                do
                    echo 40 > $gpu_bimc_io_percent
                done

		# Configure DCC module to capture critical register contents when device crashes
		for DCC_PATH in /sys/bus/platform/devices/*.dcc*
		do
			echo  0 > $DCC_PATH/enable
			echo cap >  $DCC_PATH/func_type
			echo sram > $DCC_PATH/data_sink
			echo  1 > $DCC_PATH/config_reset

			# Register specifies APC CPR closed-loop settled voltage for current voltage corner
			echo 0xb1d2c18 1 > $DCC_PATH/config

			# Register specifies SW programmed open-loop voltage for current voltage corner
			echo 0xb1d2900 1 > $DCC_PATH/config

			# Register specifies APM switch settings and APM FSM state
			echo 0xb1112b0 1 > $DCC_PATH/config

			# Register specifies CPR mode change state and also #online cores input to CPR HW
			echo 0xb018798 1 > $DCC_PATH/config

			# 0x0B1112C8 APCS_ALIAS0_L2_MAS_STS
			echo 0x0b1112c8 1 > $DCC_PATH/config

			# 0x0B1880C8 APCS_ALIAS0_MAS_STS
			echo 0x0b1880c8 1 > $DCC_PATH/config

			# 0x0B1980C8 APCS_ALIAS1_MAS_STS
			echo 0x0b1980c8 1 > $DCC_PATH/config

			# 0x0B1A80C8 APCS_ALIAS2_MAS_STS
			echo 0x0b1a80c8 1 > $DCC_PATH/config

			# 0x0B1B80C8 APCS_ALIAS3_MAS_STS
			echo 0x0b1b80c8 1 > $DCC_PATH/config

			# 0x0B0112C8 APCS_ALIAS1_L2_MAS_STS
			echo 0x0b0112c8 1 > $DCC_PATH/config

			# 0x0B0880C8 APCS_ALIAS4_MAS_STS
			echo 0x0b0880c8 1 > $DCC_PATH/config

			# 0x0B0980C8 APCS_ALIAS5_MAS_STS
			echo 0x0b0980c8 1 > $DCC_PATH/config

			# 0x0B0A80C8 APCS_ALIAS6_MAS_STS
			echo 0x0b0a80c8 1 > $DCC_PATH/config

			# 0x0B0B80C8 APCS_ALIAS7_MAS_STS
			echo 0x0b0b80c8 1 > $DCC_PATH/config

			# 0x0B112C0C APCLUS0_L2_SAW4_SPM_STS
			echo 0x0b112c0c 1 > $DCC_PATH/config

			# 0x0B189C0C APCS_ALIAS0_SAW4_SPM_STS
			echo 0x0b189c0c 1 > $DCC_PATH/config

			# 0x0B199C0C APCS_ALIAS1_SAW4_SPM_STS
			echo 0x0b199c0c 1 > $DCC_PATH/config

			# 0x0B1A9C0C APCS_ALIAS2_SAW4_SPM_STS
			echo 0x0b1a9c0c 1 > $DCC_PATH/config

			# 0x0B1B9C0C APCS_ALIAS3_SAW4_SPM_STS
			echo 0x0b1b9c0c 1 > $DCC_PATH/config

			# 0x0B012C0C APCLUS1_L2_SAW4_SPM_STS
			echo 0x0b012c0c 1 > $DCC_PATH/config

			# 0x0B089C0C APCS_ALIAS4_SAW4_SPM_STS
			echo 0x0b089c0c 1 > $DCC_PATH/config

			# 0x0B099C0C APCS_ALIAS5_SAW4_SPM_STS
			echo 0x0b099c0c 1 > $DCC_PATH/config

			# 0x0B0A9C0C APCS_ALIAS6_SAW4_SPM_STS
			echo 0x0b0a9c0c 1 > $DCC_PATH/config

			# 0x0B0B9C0C APCS_ALIAS7_SAW4_SPM_STS
			echo 0x0b0b9c0c 1 > $DCC_PATH/config

			# 0x0B1D2C0C CCI_SAW4_SPM_STS
			echo 0x0b1d2c0c 1 > $DCC_PATH/config

			# 0x0B188008 APCS_ALIAS0_APC_PWR_STATUS
			echo 0x0b188008 1 > $DCC_PATH/config

			# 0x0B198008 APCS_ALIAS1_APC_PWR_STATUS
			echo 0x0b198008 1 > $DCC_PATH/config

			# 0x0B1A8008 APCS_ALIAS2_APC_PWR_STATUS
			echo 0x0b1a8008 1 > $DCC_PATH/config

			# 0x0B1B8008 APCS_ALIAS3_APC_PWR_STATUS
			echo 0x0b1b8008 1 > $DCC_PATH/config

			# 0x0B111018 APCS_ALIAS0_L2_PWR_STATUS
			echo 0x0b111018 1 > $DCC_PATH/config

			# 0x0B088008 APCS_ALIAS4_APC_PWR_STATUS
			echo 0x0b088008 1 > $DCC_PATH/config

			# 0x0B098008 APCS_ALIAS5_APC_PWR_STATUS
			echo 0x0b098008 1 > $DCC_PATH/config

			# 0x0B0A8008 APCS_ALIAS6_APC_PWR_STATUS
			echo 0x0b0a8008 1 > $DCC_PATH/config

			# 0x0B0B8008 APCS_ALIAS7_APC_PWR_STATUS
			echo 0x0b0b8008 1 > $DCC_PATH/config

			# 0x0B011018 APCS_ALIAS1_L2_PWR_STATUS
			echo 0x0b011018 1 > $DCC_PATH/config

			# 0x0B111240 APCS_ALIAS0_CORE_HS_STATE
			echo 0x0b111240 1 > $DCC_PATH/config

			# 0x0B011240 APCS_ALIAS1_CORE_HS_STATE
			echo 0x0b011240 1 > $DCC_PATH/config

			# 0x0B1112B4 APCS_ALIAS0_DX_FSM_STATUS
			echo 0x0b1112b4 1 > $DCC_PATH/config

			# 0x0B0112B4 APCS_ALIAS1_DX_FSM_STATUS
			echo 0x0b0112b4 1 > $DCC_PATH/config

			# 0x0B1D1228 APCS_COMMON_FIRST_CORE_HANG
			echo 0x0b1d1228 1 > $DCC_PATH/config

			# 0x0B116314 APCS_C0_VMIN_SHALLOW_STATUS_REGISTER
			echo 0x0b116314 1 > $DCC_PATH/config

			# 0x0B116318 APCS_C0_VMIN_DEEP_STATUS_REGISTER
			echo 0x0b116318 1 > $DCC_PATH/config

			# 0x0B11631C APCS_C0_PERF_BOOST_SHALLOW_STATUS_REGISTER
			echo 0x0b11631c 1 > $DCC_PATH/config

			# 0x0B116320 APCS_C0_PERF_BOOST_DEEP_STATUS_REGISTER
			echo 0x0b116320 1 > $DCC_PATH/config

			echo  1 > $DCC_PATH/enable
		done

                # disable thermal & BCL core_control to update interactive gov settings
                echo 0 > /sys/module/msm_thermal/core_control/enabled
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n disable > $mode
                done
                for hotplug_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_mask
                do
                    bcl_hotplug_mask=`cat $hotplug_mask`
                    echo 0 > $hotplug_mask
                done
                for hotplug_soc_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_soc_mask
                do
                    bcl_soc_hotplug_mask=`cat $hotplug_soc_mask`
                    echo 0 > $hotplug_soc_mask
                done
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n enable > $mode
                done

                #governor settings
                echo 1 > /sys/devices/system/cpu/cpu0/online
                echo "interactive" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
                echo "19000 1401600:39000" > /sys/devices/system/cpu/cpufreq/interactive/above_hispeed_delay
                echo 85 > /sys/devices/system/cpu/cpufreq/interactive/go_hispeed_load
                echo 20000 > /sys/devices/system/cpu/cpufreq/interactive/timer_rate
                echo 1401600 > /sys/devices/system/cpu/cpufreq/interactive/hispeed_freq
                echo 0 > /sys/devices/system/cpu/cpufreq/interactive/io_is_busy
                echo "85 1401600:80" > /sys/devices/system/cpu/cpufreq/interactive/target_loads
                echo 39000 > /sys/devices/system/cpu/cpufreq/interactive/min_sample_time
                echo 40000 > /sys/devices/system/cpu/cpufreq/interactive/sampling_down_factor
                echo 652800 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq

                # re-enable thermal & BCL core_control now
                echo 1 > /sys/module/msm_thermal/core_control/enabled
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n disable > $mode
                done
                for hotplug_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_mask
                do
                    echo $bcl_hotplug_mask > $hotplug_mask
                done
                for hotplug_soc_mask in /sys/devices/soc.0/qcom,bcl.*/hotplug_soc_mask
                do
                    echo $bcl_soc_hotplug_mask > $hotplug_soc_mask
                done
                for mode in /sys/devices/soc.0/qcom,bcl.*/mode
                do
                    echo -n enable > $mode
                done

                # Bring up all cores online
                echo 1 > /sys/devices/system/cpu/cpu1/online
                echo 1 > /sys/devices/system/cpu/cpu2/online
                echo 1 > /sys/devices/system/cpu/cpu3/online
                echo 1 > /sys/devices/system/cpu/cpu4/online
                echo 1 > /sys/devices/system/cpu/cpu5/online
                echo 1 > /sys/devices/system/cpu/cpu6/online
                echo 1 > /sys/devices/system/cpu/cpu7/online

                # Enable low power modes
                echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled

                # SMP scheduler
                echo 100 > /proc/sys/kernel/sched_upmigrate
                echo 100 > /proc/sys/kernel/sched_downmigrate

                # Enable sched guided freq control
                echo 1 > /sys/devices/system/cpu/cpufreq/interactive/use_sched_load
                echo 1 > /sys/devices/system/cpu/cpufreq/interactive/use_migration_notif
                echo 200000 > /proc/sys/kernel/sched_freq_inc_notify
                echo 200000 > /proc/sys/kernel/sched_freq_dec_notify

                # Set Memory parameters
                configure_memory_parameters
	;;
	esac
	;;
esac

chown -h system /sys/devices/system/cpu/cpufreq/ondemand/sampling_rate
chown -h system /sys/devices/system/cpu/cpufreq/ondemand/sampling_down_factor
chown -h system /sys/devices/system/cpu/cpufreq/ondemand/io_is_busy

# Post-setup services
case "$target" in
    "msm8937" | "msm8953")
        echo 384 > /sys/block/mmcblk0/bdi/read_ahead_kb
        echo 384 > /sys/block/mmcblk0/queue/read_ahead_kb
        echo 384 > /sys/block/dm-0/queue/read_ahead_kb
        echo 384 > /sys/block/dm-1/queue/read_ahead_kb
# Entropy
        echo 192 > /proc/sys/kernel/random/read_wakeup_threshold
#        rm /data/system/perfd/default_values
#        start perfd
    ;;
esac

# Let kernel know our image version/variant/crm_version
if [ -f /sys/devices/soc0/select_image ]; then
    image_version="10:"
    image_version+=`getprop ro.build.id`
    image_version+=":"
    image_version+=`getprop ro.build.version.incremental`
    image_variant=`getprop ro.product.name`
    image_variant+="-"
    image_variant+=`getprop ro.build.type`
    oem_version=`getprop ro.build.version.codename`
    echo 10 > /sys/devices/soc0/select_image
    echo $image_version > /sys/devices/soc0/image_version
    echo $image_variant > /sys/devices/soc0/image_variant
    echo $oem_version > /sys/devices/soc0/image_crm_version
fi
