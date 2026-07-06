#!/system/bin/sh
MODDIR=${0%/*}
CONF_FILE="/sdcard/Android/Ylzq-module.conf"
while :
do
	SCREEN_STATE=$(dumpsys window policy 2>/dev/null | grep "mInputRestricted" | cut -d= -f2)
	if [ "$SCREEN_STATE" != "true" ]; then
		# 配置不存在自动复制模板
		if [ ! -f "$CONF_FILE" ]; then
			cp -af "${MODDIR}/files/Ylzq-module.conf" "$CONF_FILE" 2>/dev/null
		fi
		# 加载配置，屏蔽报错
		source "$CONF_FILE" 2>/dev/null
		# 扫描间隔兜底
		if [ -z "$SCAN_SECOND" ]; then
			SCAN_SECOND=10
		fi
		# 总开关判断
		if [ "$function" = "关闭" ]; then
			sed -i "/^description=/c description=总开关已关闭，修改配置function=开启恢复" "$MODDIR/module.prop" 2>/dev/null
			sleep "$SCAN_SECOND"
			continue
		fi
		# 当日统计目录
		TMP_STAT="$MODDIR/files/$(date "+%Y-%m-%d")"
		if [ ! -d "$TMP_STAT" ]; then
			rm -rf "$MODDIR/files/"* 2>/dev/null
			mkdir -p "$TMP_STAT"
			echo 0 > "$TMP_STAT/dir_count"
			echo 0 > "$TMP_STAT/file_count"
			echo 0 > "$TMP_STAT/newfile_count"
		fi
		# 合并清理目标
		ALL_TARGET=(${DEL_FULL[@]} ${DEL_INSIDE[@]})
		for TARGET in ${ALL_TARGET[@]}
		do
			IS_BLACK=0
			for BP in ${BLACK_PATH[@]}
			do
				if [ "$TARGET" = "$BP" ]; then
					IS_BLACK=1
					break
				fi
			done
			if [ $IS_BLACK -eq 1 ]; then
				sed -i "/^description=/c description=危险：配置包含禁止路径 ${TARGET}，模块已暂停，请修改配置后删除disable文件恢复" "$MODDIR/module.prop" 2>/dev/null
				touch "$MODDIR/disable"
				exit 3
			fi
			# DEL_FULL 完整删除
			if [ "${TARGET: -1}" != "/" ]; then
				if [ -e "$TARGET" ]; then
					if [ -d "$TARGET" ]; then
						rm -rf "$TARGET" 2>/dev/null
						DIR_NUM=$(cat "$TMP_STAT/dir_count" 2>/dev/null)
						echo $((DIR_NUM + 1)) > "$TMP_STAT/dir_count"
					else
						rm -rf "$TARGET" 2>/dev/null
						FILE_NUM=$(cat "$TMP_STAT/file_count" 2>/dev/null)
						echo $((FILE_NUM + 1)) > "$TMP_STAT/file_count"
					fi
				fi
			# DEL_INSIDE 仅清空内部
			else
				if [ -d "$TARGET" ] && ls -A "$TARGET" 2>/dev/null; then
					rm -rf "${TARGET}"* 2>/dev/null
					FILE_NUM=$(cat "$TMP_STAT/file_count" 2>/dev/null)
					echo $((FILE_NUM + 1)) > "$TMP_STAT/file_count"
				fi
			fi
		done

		# =====================【修复兼容安卓】路径文件监控逻辑 开始=====================
		LOG_FILE="${MODDIR}/files/路径检测.log"
		NEW_TOTAL=0
		# 遍历监控目录，屏蔽数组空值报错
		for MONITOR_DIR in ${Detection_path[@]}; do
			# 路径校验：必须以/结尾、目录存在
			if [[ -z "$MONITOR_DIR" || "${MONITOR_DIR: -1}" != "/" || ! -d "$MONITOR_DIR" ]]; then
				continue
			fi
			# 独立缓存文件，避免路径特殊字符冲突
			# 新建缓存存放文件夹，统一收纳所有对比缓存文件
            CACHE_DIR="${MODDIR}/files/monitor_cache"
            mkdir -p "$CACHE_DIR"
            CACHE_TMP="${CACHE_DIR}/.cache_$(echo -n "$MONITOR_DIR" | md5sum | awk '{print $1}')"

			# 获取当前一级文件列表，屏蔽错误输出
			CUR_LIST=$(ls -A "$MONITOR_DIR" 2>/dev/null)
			# 首次运行无缓存，仅保存列表不记录日志
			if [ ! -f "$CACHE_TMP" ]; then
				echo "$CUR_LIST" > "$CACHE_TMP"
				continue
			fi

			# 替换comm命令，安卓toybox原生兼容差值判断
			NEW_ITEMS=""
			while read item; do
				if ! grep -qxF "$item" "$CACHE_TMP"; then
					NEW_ITEMS+="$item"$''
				fi
			done <<< "$CUR_LIST"

			# 存在新增条目时写入日志并统计数量
			if [[ -n "$NEW_ITEMS" ]]; then
				NOW_TIME=$(date "+%Y-%m-%d %H:%M:%S")
				{
					echo "========================================"
					echo "检测时间：$NOW_TIME"
					echo "监控目录：$MONITOR_DIR"
					echo "新增条目："
					echo "$NEW_ITEMS"
#					echo "========================================"
#					echo ""
				} >> "$LOG_FILE"
				# 统计新增行数，过滤空行
				ITEM_COUNT=$(echo "$NEW_ITEMS" | grep -v '^$' | wc -l)
				NEW_TOTAL=$((NEW_TOTAL + ITEM_COUNT))
			fi
			# 更新缓存为本轮最新文件列表
			echo "$CUR_LIST" > "$CACHE_TMP"
		done

		# 累加当日新增计数，空值兜底0
		OLD_NEW=$(cat "$TMP_STAT/newfile_count" 2>/dev/null || echo 0)
		echo $((OLD_NEW + NEW_TOTAL)) > "$TMP_STAT/newfile_count"
		# =====================监控逻辑 结束=====================

		# 更新面板统计（新增今日新增条目展示，风格统一）
		DIR_TOTAL=$(cat "$TMP_STAT/dir_count" 2>/dev/null || echo 0)
		FILE_TOTAL=$(cat "$TMP_STAT/file_count" 2>/dev/null || echo 0)
		NEWFILE_TOTAL=$(cat "$TMP_STAT/newfile_count" 2>/dev/null || echo 0)
		sed -i "/^description=/c description=今日清理：${FILE_TOTAL}个文件 ${DIR_TOTAL}个文件夹 | 今日新增：${NEWFILE_TOTAL}个条目 | 扫描间隔${SCAN_SECOND}秒" "$MODDIR/module.prop" 2>/dev/null
	fi
	sleep "$SCAN_SECOND"
done