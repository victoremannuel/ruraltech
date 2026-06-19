// Dashboard/Home — Mapa como herói + bottom sheet dinâmico
function DashboardScreen() {
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', flexDirection: 'column', position: 'relative', background: RT.bg}}>
      {/* MAPA */}
      <div style={{position: 'absolute', inset: 0}}>
        <MapCanvas>
          {/* Propriedade (polígono) */}
          <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice" style={{position: 'absolute', inset: 0}}>
            <path d="M 30 200 L 140 150 L 260 170 L 330 250 L 340 400 L 280 500 L 150 520 L 50 460 Z"
                  fill="oklch(.45 .12 150 / .12)" stroke="oklch(.42 .11 150)" strokeWidth="2"/>
            {/* área interna */}
            <path d="M 150 280 L 230 270 L 270 330 L 240 390 L 160 390 L 130 340 Z"
                  fill="oklch(.62 .14 55 / .18)" stroke="oklch(.62 .14 55)" strokeWidth="1.8" strokeDasharray="4 3"/>
            {/* geofence de coleira */}
            <circle cx="200" cy="330" r="36" fill="none" stroke="oklch(.55 .14 150)" strokeWidth="1.3" strokeDasharray="3 3" opacity=".7"/>
          </svg>

          {/* Marcador coleira selecionada */}
          <Pin x={200} y={330} variant="collar" active label="C-042"/>
          <Pin x={150} y={250} variant="collar" label="C-017"/>
          <Pin x={260} y={290} variant="collar" label="C-088"/>
          <Pin x={110} y={380} variant="collar" status="warn"/>
          <Pin x={310} y={220} variant="gateway" label="GW-01"/>
          <Pin x={90} y={450} variant="gateway" label="GW-02"/>
        </MapCanvas>
      </div>

      {/* TOP: status + search */}
      <div style={{position: 'relative', zIndex: 3}}>
        <StatusBar/>
        <div style={{padding: '6px 12px 10px', display: 'flex', gap: 8, alignItems: 'center'}}>
          <div style={{
            flex: 1, height: 48, borderRadius: RT.r3, background: RT.bg,
            border: `1px solid ${RT.hair}`, boxShadow: RT.sh2,
            display: 'flex', alignItems: 'center', gap: 10, padding: '0 14px',
          }}>
            <Icon name="search" size={18} color={RT.inkMute}/>
            <span style={{fontFamily: RT.sans, fontSize: 14, color: RT.inkMute, flex: 1}}>
              Fazenda Doce Vale
            </span>
            <div style={{display: 'flex', alignItems: 'center', gap: 6}}>
              <span style={{fontFamily: RT.mono, fontSize: 11, color: RT.inkMute}}>12</span>
              <Icon name="filter" size={16} color={RT.ink}/>
            </div>
          </div>
          <button style={{
            width: 48, height: 48, borderRadius: RT.r3, background: RT.bg,
            border: `1px solid ${RT.hair}`, boxShadow: RT.sh2, position: 'relative',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="bell" size={20} color={RT.ink}/>
            <span style={{
              position: 'absolute', top: 10, right: 10, width: 8, height: 8,
              borderRadius: '50%', background: RT.danger, border: `2px solid ${RT.bg}`,
            }}/>
          </button>
        </div>

        {/* Chips de filtro rápido */}
        <div style={{
          padding: '0 12px', display: 'flex', gap: 6, overflowX: 'hidden',
        }}>
          <Chip active icon="layers">Todos · 14</Chip>
          <Chip dot={RT.ok} icon="collar">Coleiras · 9</Chip>
          <Chip dot={RT.warn} icon="alert">Alertas · 2</Chip>
          <Chip icon="gateway">Gateways · 3</Chip>
        </div>
      </div>

      {/* FAB de localização (direita) */}
      <div style={{
        position: 'absolute', right: 12, top: 260, zIndex: 3,
        display: 'flex', flexDirection: 'column', gap: 8,
      }}>
        {[{i:'layers'}, {i:'gps'}, {i:'compass'}].map((b,i) => (
          <button key={i} style={{
            width: 44, height: 44, borderRadius: 12, background: RT.bg,
            border: `1px solid ${RT.hair}`, boxShadow: RT.sh2,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name={b.i} size={19} color={RT.ink}/>
          </button>
        ))}
      </div>

      {/* BOTTOM SHEET — coleira selecionada */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 72, zIndex: 4,
        background: RT.bg, borderRadius: '20px 20px 0 0',
        boxShadow: '0 -8px 24px rgba(20,30,25,.10)',
        padding: '10px 0 16px',
      }}>
        <div style={{width: 36, height: 4, borderRadius: 2, background: RT.hair, margin: '2px auto 12px'}}/>
        <div style={{padding: '0 16px', display: 'flex', alignItems: 'center', gap: 12}}>
          <div style={{
            width: 44, height: 44, borderRadius: 12, background: RT.primarySoft,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="collar" size={22} color={RT.primaryDeep}/>
          </div>
          <div style={{flex: 1, minWidth: 0}}>
            <div style={{display: 'flex', alignItems: 'baseline', gap: 8}}>
              <span style={{fontFamily: RT.display, fontSize: 18, fontWeight: 700, color: RT.ink, letterSpacing: '-.02em'}}>
                Coleira 042
              </span>
              <span style={{fontFamily: RT.mono, fontSize: 12, color: RT.inkMute}}>#C-042</span>
            </div>
            <div style={{fontFamily: RT.sans, fontSize: 12, color: RT.inkSoft}}>
              Quadrante Norte · Área A2 · há 2 min
            </div>
          </div>
          <Badge tone="ok">● Online</Badge>
        </div>

        {/* Telemetria */}
        <div style={{
          margin: '14px 16px 0', padding: 12, background: RT.bgSubtle,
          borderRadius: RT.r3, display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8,
        }}>
          {[
            {i:'battery', v:'87%', l:'Bateria'},
            {i:'signal', v:'−92', l:'RSSI dB'},
            {i:'gps', v:'8 sat', l:'GPS fix'},
            {i:'thermo', v:'24°', l:'Temp'},
          ].map((s,i) => (
            <div key={i} style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2}}>
              <Icon name={s.i} size={16} color={RT.primaryDeep}/>
              <span style={{fontFamily: RT.mono, fontSize: 13, fontWeight: 700, color: RT.ink}}>{s.v}</span>
              <span style={{fontFamily: RT.sans, fontSize: 10, color: RT.inkMute, textTransform: 'uppercase', letterSpacing: '.05em'}}>{s.l}</span>
            </div>
          ))}
        </div>

        {/* Ações */}
        <div style={{padding: '12px 16px 0', display: 'flex', gap: 8}}>
          <Btn size="md" icon="polygon" style={{flex: 1}}>Geofence</Btn>
          <Btn size="md" variant="tonal" icon="route" style={{flex: 1}}>Conduzir</Btn>
          <button style={{
            width: 48, height: 48, borderRadius: RT.r3, background: RT.bg,
            border: `1px solid ${RT.hair}`, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
          }}>
            <Icon name="more" size={20}/>
          </button>
        </div>
      </div>

      {/* TAB BAR */}
      <div style={{marginTop: 'auto', position: 'relative', zIndex: 2}}>
        <TabBar active="map"/>
        <NavPill/>
      </div>
    </div>
  );
}

function Pin({ x, y, variant, active, status, label }) {
  const color = variant === 'gateway' ? RT.accent : (status === 'warn' ? RT.warn : RT.primaryDeep);
  const size = active ? 44 : 32;
  return (
    <div style={{
      position: 'absolute', left: x, top: y,
      transform: `translate(-50%, -100%)`,
    }}>
      {active && (
        <div style={{
          position: 'absolute', left: '50%', top: '100%',
          transform: 'translate(-50%, -50%)', width: 72, height: 72,
          borderRadius: '50%', background: color, opacity: .18,
        }}/>
      )}
      <div style={{
        width: size, height: size, borderRadius: '50% 50% 50% 0',
        transform: 'rotate(-45deg)', background: color,
        border: '3px solid #fff', boxShadow: RT.sh2,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <div style={{transform: 'rotate(45deg)', color: '#fff'}}>
          <Icon name={variant === 'gateway' ? 'gateway' : 'collar'} size={size === 44 ? 18 : 14} color="#fff" stroke={2.2}/>
        </div>
      </div>
      {label && !active && (
        <div style={{
          position: 'absolute', left: '50%', top: '100%', marginTop: 4,
          transform: 'translateX(-50%)',
          fontFamily: RT.mono, fontSize: 10, fontWeight: 600, color: RT.ink,
          background: 'rgba(255,255,255,.9)', padding: '1px 5px', borderRadius: 4,
          whiteSpace: 'nowrap', border: `1px solid ${RT.hair}`,
        }}>{label}</div>
      )}
    </div>
  );
}

window.DashboardScreen = DashboardScreen;
window.Pin = Pin;
