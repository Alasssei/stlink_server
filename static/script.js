let selectedModel = "";
let selectedFile = "";
let fastModeInterval = null;
let boardCount = 0;
let lastScreen = 'screen-main';
let currentRshkIndex = 0;
const rshkFiles = [];
let debugVisible = false; // debug прихований за замовчуванням

function generateRshkData() {
    rshkFiles.length = 0;
    for (let i = 1; i <= 20; i++) {
        for (let sub = 1; sub <= 2; sub++) {
            const start = (i - 1) * 10 + (sub === 1 ? 1 : 6);
            const end = start + 4;
            rshkFiles.push({
                path: `rshk/PTL_LED2812_KIOTO_F030_${i}_${sub}`,
                label: `${start}-${end}`
            });
        }
    }
}
generateRshkData();

function toggleDebug() {
    debugVisible = !debugVisible;
    const btn = document.getElementById('debug-toggle-btn');
    const entries = document.querySelectorAll('.debug-entry');
    entries.forEach(el => {
        el.style.display = debugVisible ? 'block' : 'none';
    });
    btn.innerText = debugVisible ? '🐛 DEBUG: ON' : '🐛 DEBUG: OFF';
    btn.style.borderColor = debugVisible ? '#ff9800' : '#444';
    btn.style.color = debugVisible ? '#ff9800' : '#555';
}

function openMenu(id) {
    stopFastMode();
    if (!id.includes('flash')) {
        boardCount = 0;
        document.getElementById('session-count').innerText = "0";
        document.getElementById('log').innerHTML = "[SYS]: Готово до роботи...";
    }

    if (id !== 'screen-flash') {
        document.getElementById('direction-selector-container').classList.add('hidden');
    }

    if (!id.includes('flash')) lastScreen = id;
    document.querySelectorAll('.container > div[id^="screen"]').forEach(s => s.classList.add('hidden'));

    const target = document.getElementById(id);
    if (target) target.classList.remove('hidden');
}

function openModel(model) {
    selectedModel = model;
    document.getElementById('monitor-model-name').innerText = model.replace('_', '/');
    openMenu('screen-monitor');
}

function openPblRshk() {
    currentRshkIndex = 0;
    document.getElementById('direction-selector-container').classList.remove('hidden');
    updateRshkDisplay();
    selectFinal(`PBL_RSHK (${rshkFiles[0].label})`, rshkFiles[0].path, 'screen-plates');
}

function stepDirection(step) {
    stopFastMode();
    document.getElementById('fastMode').checked = false;

    currentRshkIndex += step;
    if (currentRshkIndex < 0) currentRshkIndex = rshkFiles.length - 1;
    if (currentRshkIndex >= rshkFiles.length) currentRshkIndex = 0;

    updateRshkDisplay();
}

function updateRshkDisplay() {
    const current = rshkFiles[currentRshkIndex];
    document.getElementById('direction-label').innerText = current.label;

    selectedFile = current.path;
    document.getElementById('display-name').innerText = `PBL_RSHK (${current.label})`;

    const log = document.getElementById('log');
    log.innerHTML = `<span style="color: #00adb5">[SYS]: Вибрано напрямки ${current.label}</span>\n`;
    log.innerHTML += `<span style="color: #0f0">[SYS]: Файл: ${selectedFile}</span>\n`;
    log.scrollTop = log.scrollHeight;
}

function playSuccessSound() {
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const oscillator = audioCtx.createOscillator();
    const gainNode = audioCtx.createGain();

    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(800, audioCtx.currentTime);

    gainNode.gain.setValueAtTime(0.1, audioCtx.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + 0.2);

    oscillator.connect(gainNode);
    gainNode.connect(audioCtx.destination);

    oscillator.start();
    oscillator.stop(audioCtx.currentTime + 0.2);
}

function selectFinal(displayName, fileName, originScreenId) {
    let folder = "";

    if (!fileName.includes('/')) {
        if (originScreenId === 'screen-new-monitor') folder = "monitors/new/";
        else if (originScreenId === 'screen-old-raspi') folder = "monitors/raspi/";
        else if (originScreenId === 'screen-old-ctrl') folder = "monitors/ctrl/";
        else if (originScreenId === 'screen-plates' ||
                 originScreenId === 'screen-monitor' ||
                 originScreenId === 'screen-stm-u4') {
            folder = "indicators/";
        }
    }

    selectedFile = folder + fileName;

    if (!selectedFile.includes('rshk/')) {
        document.getElementById('direction-selector-container').classList.add('hidden');
    }

    document.getElementById('display-name').innerText = displayName;
    document.getElementById('display-sub').innerText = "Готовий до запису";
    document.getElementById('back-to-prev-screen').onclick = () => openMenu(originScreenId);

    const log = document.getElementById('log');
    log.innerHTML = `<span style="color: #0f0">[SYS]: Файл: ${selectedFile}</span>\n`;

    document.getElementById('bar').style.width = '0%';
    document.getElementById('percent-text').innerText = "Очікування";
    document.getElementById('flash-btn').disabled = false;

    stopFastMode();
    document.getElementById('fastMode').checked = false;
    openMenu('screen-flash');
}

document.getElementById('fastMode').addEventListener('change', function() {
    if (this.checked) startFastMode(); else stopFastMode();
});

function startFastMode() {
    document.getElementById('wait-timer').classList.add('hidden');
    if (fastModeInterval) clearInterval(fastModeInterval);
    fastModeInterval = setInterval(async () => {
        try {
            const res = await fetch('/check_connection');
            const data = await res.json();
            if (data.status === "connected") {
                clearInterval(fastModeInterval);
                triggerFlash();
            }
        } catch (e) { console.log("Помилка сервера"); }
    }, 2000);
}

function stopFastMode() {
    if (fastModeInterval) clearInterval(fastModeInterval);
    fastModeInterval = null;
    document.getElementById('wait-timer').classList.add('hidden');
}

function appendDebugLog(log, text) {
    const span = document.createElement('span');
    span.className = 'debug-entry';
    span.style.color = '#ff9800';
    span.style.fontSize = '0.7rem';
    span.style.display = debugVisible ? 'block' : 'none';
    span.textContent = text;
    log.appendChild(span);
    log.appendChild(document.createTextNode('\n'));
}

async function triggerFlash() {
    const btn = document.getElementById('flash-btn');
    const log = document.getElementById('log');
    const bar = document.getElementById('bar');
    const percentText = document.getElementById('percent-text');
    const isFastMode = document.getElementById('fastMode').checked;

    btn.disabled = true;
    bar.style.width = "30%";
    percentText.innerText = "Запис...";

    try {
        const response = await fetch(`/start_flash?file=${encodeURIComponent(selectedFile)}`);
        if (!response.ok) throw new Error(`Сервер: ${response.status}`);
        const data = await response.json();

        if (data.status === "success") {
            boardCount++;
            document.getElementById('session-count').innerText = boardCount;
            bar.style.width = "100%";
            percentText.innerText = "Успішно!";
            log.innerHTML += `<span style="color:#0f0">[OK]: Плата №${boardCount} готова</span>\n`;
            playSuccessSound();

            if (data.output) {
                appendDebugLog(log, data.output);
            }

            if (isFastMode) runCooldown(3);
        } else {
            bar.style.width = "0%";
            percentText.innerText = "Помилка!";

            const errorMsg = data.message || "Невідома помилка";
            log.innerHTML += `<span class="text-danger"><b>[ПОМИЛКА]: ${errorMsg}</b></span>\n`;

            if (data.output || data.full_log) {
                appendDebugLog(log, data.full_log || data.output);
            }

            if (isFastMode) {
                log.innerHTML += `<span class="text-warning">[FAST]: Продовжую пошук...</span>\n`;
                setTimeout(startFastMode, 2000);
            }
        }
    } catch (err) {
        bar.style.width = "0%";
        percentText.innerText = "Збій!";
        log.innerHTML += `<span class="text-danger">[СИСТЕМНА ПОМИЛКА]: ${err.message}</span>\n`;
        if (isFastMode) setTimeout(startFastMode, 3000);
    } finally {
        btn.disabled = false;
        log.scrollTop = log.scrollHeight;
    }
}

function runCooldown(seconds) {
    const timerDiv = document.getElementById('wait-timer');
    const timerText = document.getElementById('timer-seconds');
    let timeLeft = seconds;

    timerDiv.classList.remove('hidden');
    timerText.innerText = timeLeft + "s";

    const cd = setInterval(() => {
        timeLeft--;
        timerText.innerText = timeLeft + "s";
        if (timeLeft <= 0) {
            clearInterval(cd);
            timerDiv.classList.add('hidden');
            if (document.getElementById('fastMode').checked) {
                startFastMode();
            }
        }
    }, 1000);
}