# Runs inside qrenderdoc (--python). Reads job.json {ident, out, name, count, gap}: connects to the WE process started
# under renderdoccmd, triggers `count` single-frame captures `gap` s apart, and saves each frame's swapchain image as PNG
# (works while the desktop is locked, as long as WE keeps rendering). Writes <out>/<name>_report.txt.
import os, json, time
JOB = json.load(open(r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\job.json'))
OUT = JOB['out']; os.makedirs(OUT, exist_ok=True)
log = open(os.path.join(OUT, JOB['name'] + '_report.txt'), 'w', encoding='utf-8')
def P(*a):
    log.write(' '.join(str(x) for x in a) + '\n'); log.flush()
try:
    import renderdoc as rd
    tc = rd.CreateTargetControl('', int(JOB['ident']), 'claude-grab', True)
    if tc is None:
        P('ERROR: no target'); raise SystemExit
    P('target', tc.GetTarget(), 'api', tc.GetAPI(), 'pid', tc.GetPID())
    capdir = os.path.dirname(JOB.get('capprefix', r'K:\DeepWorkspace\wem-images2\tools\peer\requests\rd_grab\cap\we'))
    before = set(os.listdir(capdir)) if os.path.isdir(capdir) else set()
    paths = []
    for i in range(int(JOB['count'])):
        tc.TriggerCapture(1); t0 = time.time(); got = None
        while time.time() - t0 < 30 and not got:
            m = tc.ReceiveMessage(None)
            if m.type == rd.TargetControlMessageType.NewCapture and os.path.basename(m.newCapture.path) not in before:
                got = m.newCapture.path; before.add(os.path.basename(got))
        P('capture', i, got, 'at', round(time.time(), 3)); paths.append(got)
        time.sleep(float(JOB.get('gap', 0.5)))
    tc.Shutdown()
    for i, path in enumerate(p for p in paths if p):
        cap = rd.OpenCaptureFile(); cap.OpenFile(path, '', None)
        st, ctrl = cap.OpenCapture(rd.ReplayOptions(), None)
        acts = []
        def walk(a):
            for x in a: acts.append(x); walk(x.children)
        walk(ctrl.GetRootActions())
        ctrl.SetFrameEvent(acts[-1].eventId, True)
        sw = [t for t in ctrl.GetTextures() if t.creationFlags & rd.TextureCategory.SwapBuffer]
        P('frame', i, 'actions', len(acts), 'swapbuffers', [(t.width, t.height) for t in sw])
        for k, t in enumerate(sw):
            s = rd.TextureSave(); s.resourceId = t.resourceId; s.destType = rd.FileType.PNG; s.alpha = rd.AlphaMapping.Discard
            f = os.path.join(OUT, '%s_f%d_sw%d.png' % (JOB['name'], i, k))
            P('  save', f, ctrl.SaveTexture(s, f))
        ctrl.Shutdown(); cap.Shutdown()
except SystemExit:
    pass
except Exception:
    import traceback; P('EXCEPTION', traceback.format_exc())
finally:
    log.close(); os._exit(0)
