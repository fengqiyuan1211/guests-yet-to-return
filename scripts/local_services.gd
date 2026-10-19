extends Node
## Desktop development backends. Secrets stay in each Python service's .env.
var states: Dictionary = {}
var enabled := false
var report_path := ""
var boot_pid := -1
var boot_msec := 0
var starting := false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	var explicit:= "--start-local-services" in OS.get_cmdline_user_args()
	if "--no-local-services" in OS.get_cmdline_user_args(): return
	if not explicit:
		if DisplayServer.get_name()=="headless": return
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--slot-wallet=") or arg.begins_with("--dialogue-save=") or arg.begins_with("--game-save="): return
	if OS.get_name() not in ["macOS","Windows","Linux","FreeBSD","NetBSD","OpenBSD"]: return
	enabled=true
	states={"image":{"status":"starting"},"feedback":{"status":"starting"}}
	call_deferred("_start")

func _start() -> void:
	if starting: return
	starting=true
	states={"image":{"status":"starting"},"feedback":{"status":"starting"}}
	report_path=""
	await _launch()
	starting=false

func _launch() -> void:
	var directory:=ProjectSettings.globalize_path("res://")
	var helper:=directory.path_join("services/auto_start.py")
	if not FileAccess.file_exists(helper):
		directory=OS.get_executable_path().get_base_dir()
		helper=directory.path_join("services/auto_start.py")
	if not FileAccess.file_exists(helper):
		_fail("本地服务文件缺失，请同步完整工程。")
		return
	var state_dir:=ProjectSettings.globalize_path("user://local_services")
	DirAccess.make_dir_recursive_absolute(state_dir)
	report_path=state_dir.path_join("startup-%d-%d.json" % [OS.get_process_id(),Time.get_ticks_usec()])
	var image_url:="http://127.0.0.1:8787"
	var image_config: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/diy_image_service.json"))
	if image_config is Dictionary: image_url=str(image_config.get("service_url",image_url))
	var local:=ConfigFile.new()
	if local.load("user://diy_image_service.cfg")==OK: image_url=str(local.get_value("service","url",image_url))
	var feedback_url: String=CustomerService.endpoint
	var args:=PackedStringArray([helper,"--project-dir",directory,"--state-dir",state_dir,"--report",report_path,"--image-url",image_url,"--feedback-url",feedback_url])
	for candidate in _python_candidates(directory):
		boot_pid=OS.create_process(candidate,args,false)
		if boot_pid>0: break
	if boot_pid<=0:
		_fail("没有找到 Python，请先安装 Python 3.10 及以上版本。")
		return
	boot_msec=Time.get_ticks_msec()
	while Time.get_ticks_msec()-boot_msec<40000:
		_refresh()
		if _settled(): return
		if not OS.is_process_running(boot_pid):
			await get_tree().create_timer(.1).timeout
			_refresh()
			if not _settled(): _fail("本地服务未能启动，请检查 Python 和服务配置。")
			return
		await get_tree().create_timer(.25).timeout
	_fail("本地服务启动超时，请稍后重试。")

func _python_candidates(directory: String) -> Array[String]:
	var candidates: Array[String]=[]
	var suffix:="Scripts/python.exe" if OS.get_name()=="Windows" else "bin/python"
	for prefix in ["services/cocktail-image-service/.venv",".venv"]:
		var path:=directory.path_join(prefix).path_join(suffix)
		if FileAccess.file_exists(path): candidates.append(path)
	var user_dir:=OS.get_environment("USERPROFILE" if OS.get_name()=="Windows" else "HOME")
	var bundled:=user_dir.path_join(".cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3")
	if FileAccess.file_exists(bundled): candidates.append(bundled)
	var windows:=OS.get_name()=="Windows"
	for path in OS.get_environment("PATH").split(";" if windows else ":",false):
		for name in (["python.exe","python3.exe"] if windows else ["python3","python"]):
			var executable:=path.path_join(name)
			if FileAccess.file_exists(executable) and executable not in candidates: candidates.append(executable)
	if not windows and FileAccess.file_exists("/usr/bin/python3") and "/usr/bin/python3" not in candidates: candidates.append("/usr/bin/python3")
	return candidates

func _refresh() -> void:
	if report_path.is_empty() or not FileAccess.file_exists(report_path): return
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if data is Dictionary and data.get("image") is Dictionary and data.get("feedback") is Dictionary: states=data

func _settled() -> bool:
	return states.get("image",{}).get("status")!="starting" and states.get("feedback",{}).get("status")!="starting"

func _fail(message: String) -> void:
	for kind in ["image","feedback"]:
		if states.get(kind,{}).get("status")=="starting": states[kind]={"status":"error","message":message}
	push_warning(message)

func ensure_ready(kind: String) -> bool:
	if not enabled: return true
	# A manual retry rechecks the backends instead of keeping an old startup error.
	if states.get(kind,{}).get("status")=="error" and not starting:
		await _start()
	var deadline:=Time.get_ticks_msec()+40000
	while states.get(kind,{}).get("status")=="starting" and Time.get_ticks_msec()<deadline:
		_refresh()
		await get_tree().create_timer(.1).timeout
	return states.get(kind,{}).get("status") in ["ready","remote","disabled"]

func failure_message(kind: String) -> String:
	return str(states.get(kind,{}).get("message","服务暂未就绪，请稍后重试。"))
