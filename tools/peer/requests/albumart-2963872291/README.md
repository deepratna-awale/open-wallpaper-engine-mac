# 2963872291 Alice City: album art (item 7), partial
- **Capture method:** RenderDoc swapchain grabs (see ../rd_grab), because the Windows session is locked.
- **What's here:** only `alice_nomusic_f0/f1_sw0.png`, the **no-media state**. The cover shows a grey placeholder with a music note, and the text reads "--/--".
- **Not captured:** the **track playing** and **track change** states. They need a media app publishing to Windows' media session (SMTC). That can't be driven reliably while the session is locked and the owner is away. They'll be captured once someone is at the PC.
