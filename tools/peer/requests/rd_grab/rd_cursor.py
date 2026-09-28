# Runs inside qrenderdoc (--python). Cursor-effects stills via RenderDoc (session locked, desktop capture black).
# job_cursor.json: {ident, we, out, projects:[...]} -- for each project in ../cursor-effects/shots.json: opens it on
# monitor 2, parks the cursor, grabs a frame, then for each still moves the cursor (SetCursorPos, per-monitor DPI
# aware), waits 1 s, grabs a frame. Logs GetCursorPos after each move. Sweeps are skipped (single frames only).
import os, json, time, subprocess, ctypes
from ctypes import wintypes
JOB = json.load(open(r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\job_cursor.json'))
OUT = JOB['out']; os.makedirs(OUT, exist_ok=True)
log = open(os.path.join(OUT, 'rd_cursor_report.txt'), 'w', encoding='utf-8')
def P(*a):
    log.write(' '.join(str(x) for x in a) + '\n'); log.flush()
u = ctypes.windll.user32
u.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
MX, MY = 1920, 0   # monitor 2 origin (physical px)
def cur():
    p = wintypes.POINT(); ok = u.GetCursorPos(ctypes.byref(p)); return (p.x - MX, p.y - MY, bool(ok))
try:
    import renderdoc as rd
    capdir = r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\cap'
    before = set(os.listdir(capdir))
    tc = rd.CreateTargetControl('', int(JOB['ident']), 'claude-cursor', True)
    P('target pid', tc.GetPID())
    def grab(tag):
        tc.TriggerCapture(1); t0 = time.time()
        while time.time() - t0 < 30:
            m = tc.ReceiveMessage(None)
            if m.type == rd.TargetControlMessageType.NewCapture and os.path.basename(m.newCapture.path) not in before:
                before.add(os.path.basename(m.newCapture.path)); jobs.append((tag, m.newCapture.path)); return
        P('  no capture for', tag)
    jobs = []
    shots = json.load(open(r'K:\DeepWorkspace\wem-images2\tools\peer\requests\cursor-effects\shots.json'))
    we = JOB['we']
    for s in shots:
        if s['project'] not in JOB['projects']: continue
        r = u.SetCursorPos(MX + 40, MY + 40)
        subprocess.call([we + r'\wallpaper64.exe', '-control', 'openWallpaper', '-file',
                         we + r'\projects\myprojects\%s\project.json' % s['project'], '-monitor', '1'])
        time.sleep(5)
        P(s['project'], 'park setcursor', r, 'cursor', cur()); grab('%s_park' % s['project'])
        for x, y in s.get('stills', []):
            r = u.SetCursorPos(MX + int(x), MY + int(y)); time.sleep(1.0)
            P(s['project'], 'still', x, y, 'setcursor', r, 'cursor', cur()); grab('%s_%d_%d' % (s['project'], x, y))
    tc.Shutdown()
    for tag, path in jobs:
        cap = rd.OpenCaptureFile(); cap.OpenFile(path, '', None)
        st, ctrl = cap.OpenCapture(rd.ReplayOptions(), None)
        sw = [t for t in ctrl.GetTextures() if t.creationFlags & rd.TextureCategory.SwapBuffer]
        acts = ctrl.GetRootActions(); ctrl.SetFrameEvent(acts[-1].eventId, True)
        for k, t in enumerate(sw):
            sv = rd.TextureSave(); sv.resourceId = t.resourceId; sv.destType = rd.FileType.PNG; sv.alpha = rd.AlphaMapping.Discard
            f = os.path.join(OUT, '%s.png' % tag if k == 0 else '%s_sw%d.png' % (tag, k))
            P('save', f, ctrl.SaveTexture(sv, f))
        ctrl.Shutdown(); cap.Shutdown()
except Exception:
    import traceback; P('EXCEPTION', traceback.format_exc())
finally:
    log.close(); os._exit(0)
