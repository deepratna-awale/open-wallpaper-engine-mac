# Runs inside qrenderdoc (--python). job_timed.json {ident, we, out, monitor, shots:[{project, tag, stills:[s...]}]}:
# for each project opens it via wallpaper64 -control, then triggers one-frame captures as close as possible to each
# still time (seconds after the open command), and saves each frame's swapchain as <out>/<tag>_t<still>.png.
# The actual trigger time is logged (capture latency is a few hundred ms). Works with the screen covered or locked.
import os, json, time, subprocess
JOB = json.load(open(r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\job_timed.json'))
OUT = JOB['out']; os.makedirs(OUT, exist_ok=True)
log = open(os.path.join(OUT, 'rd_timed_report.txt'), 'w', encoding='utf-8')
def P(*a):
    log.write(' '.join(str(x) for x in a) + '\n'); log.flush()
try:
    import renderdoc as rd
    capdir = r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\cap'
    os.makedirs(capdir, exist_ok=True); before = set(os.listdir(capdir))
    tc = rd.CreateTargetControl('', int(JOB['ident']), 'claude-timed', True)
    jobs = []
    for s in JOB['shots']:
        subprocess.call([JOB['we'] + r'\wallpaper64.exe', '-control', 'openWallpaper', '-file', JOB['we'] + r'\projects\defaultprojects\retro\project.json', '-monitor', str(JOB['monitor'])])
        time.sleep(3)
        subprocess.call([JOB['we'] + r'\wallpaper64.exe', '-control', 'openWallpaper', '-file', JOB['we'] + r'\projects\myprojects\%s\project.json' % s['project'], '-monitor', str(JOB['monitor'])])
        t0 = time.time()
        for st in s['stills']:
            while time.time() - t0 < st: time.sleep(0.005)
            trig = time.time() - t0; tc.TriggerCapture(1); w0 = time.time()
            while time.time() - w0 < 30:
                m = tc.ReceiveMessage(None)
                if m.type == rd.TargetControlMessageType.NewCapture and os.path.basename(m.newCapture.path) not in before:
                    before.add(os.path.basename(m.newCapture.path)); jobs.append(('%s_t%s' % (s['tag'], st), m.newCapture.path))
                    P(s['project'], 'still', st, 'triggered at %.3f s' % trig, 'frame', m.newCapture.frameNumber); break
    tc.Shutdown()
    for name, path in jobs:
        cap = rd.OpenCaptureFile(); cap.OpenFile(path, '', None)
        st, ctrl = cap.OpenCapture(rd.ReplayOptions(), None)
        ctrl.SetFrameEvent(ctrl.GetRootActions()[-1].eventId, True)
        for t in ctrl.GetTextures():
            if t.creationFlags & rd.TextureCategory.SwapBuffer:
                sv = rd.TextureSave(); sv.resourceId = t.resourceId; sv.destType = rd.FileType.PNG; sv.alpha = rd.AlphaMapping.Discard
                ctrl.SaveTexture(sv, os.path.join(OUT, name + '.png'))
        ctrl.Shutdown(); cap.Shutdown()
except Exception:
    import traceback; P('EXCEPTION', traceback.format_exc())
finally:
    log.close(); os._exit(0)
