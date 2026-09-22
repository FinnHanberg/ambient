/* ═══════════════════════════════════════════════════════════════════════════
   WORLD — the ground.

   Lifted verbatim from ~/Claude 1/displace/canvas/src/world.js (the CONTENT
   studio). The zero-camera guard below was paid for there; inheriting the file
   inherits the law rather than rediscovering it. A camera over a plane of nodes: wheel pans, pinch or
   ⌘-wheel zooms about the cursor, dragging the ground pans, dragging a
   selected node hands the delta to the node. Nothing here knows what a node
   shows.
   ═══════════════════════════════════════════════════════════════════════════ */
export function createWorld(ground, plane, hooks){
  const cam = { x:0, y:0, z:1 };
  const apply = () => { plane.style.transform = `translate3d(${cam.x}px,${cam.y}px,0) scale(${cam.z})`; hooks.onCamera && hooks.onCamera(cam); };
  const toWorld = (sx, sy) => [(sx - cam.x)/cam.z, (sy - cam.y)/cam.z];

  /* ⛔ A camera is never zero. `fitRect` used to divide by whatever the ground
     reported, and a ground that reports zero height — a hidden tab, a preview
     pane, a container mid-layout — put `scale(0)` on the plane, which looks
     exactly like a blank page and, once autosaved, survives the reload. */
  const clampZ = z => Number.isFinite(z) ? Math.min(4, Math.max(.08, z)) : 1;
  function zoomAt(sx, sy, f){
    const z = clampZ(cam.z * f);
    const [wx, wy] = toWorld(sx, sy);
    cam.z = z; cam.x = sx - wx*z; cam.y = sy - wy*z; apply();
  }
  function fitRect(r, pad = .1, animate = true){
    const W = ground.clientWidth, H = ground.clientHeight;
    if(!(W > 0 && H > 0) || !(r.w > 0) || !(r.h > 0)) return;   /* nothing to fit to */
    const z = clampZ(Math.min(W*(1-pad*2)/r.w, H*(1-pad*2)/r.h));
    const nx = W/2 - (r.x + r.w/2)*z, ny = H/2 - (r.y + r.h/2)*z;
    if(![nx, ny].every(Number.isFinite)) return;
    if(!animate){ cam.x = nx; cam.y = ny; cam.z = z; apply(); return; }
    const from = { ...cam }, t0 = performance.now();
    (function step(now){
      const u = Math.min(1, (now - t0)/520), e = 1 - Math.pow(1-u, 3);
      cam.x = from.x + (nx-from.x)*e; cam.y = from.y + (ny-from.y)*e; cam.z = from.z + (z-from.z)*e; apply();
      if(u < 1) requestAnimationFrame(step);
    })(t0);
  }

  ground.addEventListener('wheel', e => {
    e.preventDefault();
    if(e.ctrlKey || e.metaKey) zoomAt(e.clientX, e.clientY, Math.exp(-e.deltaY * .012));
    else { cam.x -= e.deltaX; cam.y -= e.deltaY; apply(); }
  }, { passive:false });

  let down = null;
  ground.addEventListener('pointerdown', e => {
    if(e.button !== 0 || e.target.closest('#tool,#pill')) return;
    const node = e.target.closest('.node');
    down = { x:e.clientX, y:e.clientY, cx:cam.x, cy:cam.y, node, moved:false,
             nudge: node && node.classList.contains('sel') };
    ground.setPointerCapture(e.pointerId);
    if(down.nudge) hooks.onHold && hooks.onHold(node, true);
  });
  ground.addEventListener('pointermove', e => {
    if(!down) return;
    const dx = e.clientX - down.x, dy = e.clientY - down.y;
    if(!down.moved && Math.hypot(dx, dy) < 4) return;
    down.moved = true;
    if(down.nudge){
      const r = down.node.getBoundingClientRect();
      hooks.onNudge && hooks.onNudge(down.node, (e.clientX - (down.lx ?? down.x))/r.width, (e.clientY - (down.ly ?? down.y))/r.height);
      down.lx = e.clientX; down.ly = e.clientY;
    } else { cam.x = down.cx + dx; cam.y = down.cy + dy; apply(); ground.classList.add('drag'); }
  });
  const up = e => {
    if(!down) return;
    ground.classList.remove('drag');
    if(down.nudge) hooks.onHold && hooks.onHold(down.node, false);
    if(!down.moved) hooks.onSelect && hooks.onSelect(down.node);
    down = null;
  };
  ground.addEventListener('pointerup', up); ground.addEventListener('pointercancel', up);
  const worldRect = el => { const r = el.getBoundingClientRect(); const [x,y] = toWorld(r.left, r.top); return { x, y, w:r.width/cam.z, h:r.height/cam.z }; };
  ground.addEventListener('dblclick', e => {
    const node = e.target.closest('.node'); if(!node) return;
    fitRect(worldRect(node), .08);
  });

  /* the plane holds absolutely-positioned rows, so it has no intrinsic box of
     its own — the extent is the union of what is on it. */
  function contentRect(){
    const kids = plane.children;
    if(!kids.length) return { x:0, y:0, w:1, h:1 };
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for(const k of kids){
      const r = worldRect(k);
      x0 = Math.min(x0, r.x); y0 = Math.min(y0, r.y);
      x1 = Math.max(x1, r.x + r.w); y1 = Math.max(y1, r.y + r.h);
    }
    return { x:x0, y:y0, w:Math.max(1, x1-x0), h:Math.max(1, y1-y0) };
  }
  /* a camera restored from a document, only if it is one */
  const setCam = c => {
    if(!c || ![c.x, c.y, c.z].every(Number.isFinite) || c.z < .08 || c.z > 4) return false;
    Object.assign(cam, c); apply(); return true;
  };
  return { cam, apply, setCam, zoomAt, fitRect, toWorld, worldRect, contentRect,
           fitAll(animate = true){ fitRect(contentRect(), .08, animate); } };
}
