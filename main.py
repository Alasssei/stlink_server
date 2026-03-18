import os
import subprocess
from flask import Flask, render_template, request, jsonify

app = Flask(__name__)

# Шляхи на Raspberry Pi
BASE_DIR = "/home/aboba/stlink_server"
FIRMWARE_DIR = os.path.join(BASE_DIR, "firmwares")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/check_connection')
def check_connection():
    try:
        result = subprocess.run(['lsusb'], capture_output=True, text=True)
        if "STMicroelectronics ST-LINK" in result.stdout:
            return jsonify({"status": "connected"})
        return jsonify({"status": "disconnected"})
    except:
        return jsonify({"status": "error"}), 500

@app.route('/start_flash')
@app.route('/flash')
def flash_process():
    file_name = request.args.get('file') or request.args.get('filename')

    if not file_name:
        return jsonify({"status": "error", "message": "Назва файлу не отримана"}), 400

    file_name = file_name.lstrip('/')

    target_path = None
    for ext in ['', '.hex', '.bin']:
        check_path = os.path.join(FIRMWARE_DIR, file_name + ext)
        if os.path.exists(check_path):
            target_path = check_path
            break

    if not target_path:
        return jsonify({
            "status": "error",
            "message": f"Файл не знайдено: {file_name}",
            "checked_dir": FIRMWARE_DIR
        }), 404

    is_bin = target_path.lower().endswith('.bin')

    if is_bin:
        flash_command = f"program {target_path} 0x08000000 verify"
    else:
        flash_command = f"program {target_path} verify"

    cmd = [
        "openocd",
        "-f", "interface/stlink.cfg",
        "-f", "target/stm32f0x.cfg",
        "-c", "init",
        "-c", flash_command,
        "-c", "reset run",
        "-c", "exit"
    ]

    try:
        process = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if process.returncode == 0:
            return jsonify({
                "status": "success",
                "message": "Прошивка завершена успішно!",
                "output": process.stdout
            })
        else:
            error_output = process.stderr
            friendly_msg = "Помилка OpenOCD"

            if "checksum mismatch" in error_output or "Verify Failed" in error_output:
                friendly_msg = "Помилка верифікації (невірний адрес або збій запису)"
            elif "no flash bank found" in error_output:
                friendly_msg = "Адреса прошивки поза межами пам'яті чіпа"
            elif "Error: open failed" in error_output:
                friendly_msg = "ST-Link не знайдено (перевір USB)"
            elif "Target not examined" in error_output:
                friendly_msg = "Плата не відповідає (перевір живлення/SWD)"

            return jsonify({
                "status": "error",
                "message": friendly_msg,
                "full_log": error_output
            })

    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

if __name__ == '__main__':
    print(f"Сервер запускається. Папка з прошивками: {FIRMWARE_DIR}")
    app.run(host='0.0.0.0', port=5000, debug=True)