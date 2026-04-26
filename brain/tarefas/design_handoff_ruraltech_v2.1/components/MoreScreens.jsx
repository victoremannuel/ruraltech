// Device Details, Geofence, Herding, Events, Profile, Design System

// ── DEVICE DETAILS ─
function DeviceDetailsScreen() {
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', flexDirection: 'column', background: RT.bgSubtle, position: 'relative'}}>
      <StatusBar/>
      <AppBar title="Coleira 042" subtitle="Fazenda Doce Vale · A2" trailing={[{icon: 'clipboard'}, {icon: 'more'}]}/>

      <div style={{flex: 1, overflow: 'hidden', padding: 14, display: 'flex', flexDirection: 'column', gap: 12}}>
        {/* Hero status */}
        <div style={{
          padding: 16, borderRadius: RT.r4,
          background: `linear-gradient(135deg, ${RT.primaryDeep} 0%, ${RT.primary} 100%)`,
          color: '#fff', position: 'relative', overflow: 'hidden',
        }}>
          <svg width="120" height="120" viewBox="0 0 120 120" style={{position: 'absolute', right: -20, top: -20, opacity: .15}}>
            <circle cx="60" cy="60" r="50" stroke="#fff" strokeWidth="1" fill="none"/>
            <circle cx="60" cy="60" r="30" stroke="#fff" strokeWidth="1" fill="none"/>
          </svg>
          <div style={{display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10}}>
            <Badge tone="primary" style={{background: 'rgba(255,255,255,.2)', color: '#fff'}}>● Online</Badge>
            <span style={{fontFamily: RT.mono, fontSize: 11, color: 'rgba(255,255,255,.7)'}}>há 2 min</span>
          </div>
          <div style={{fontFamily: RT.display, fontSize: 22, fontWeight: 700, letterSpacing: '-.02em'}}>Saúde da coleira</div>
          <div style={{fontFamily: RT.sans, fontSize: 13, opacity: .8, marginTop: 2}}>Todos sistemas operacionais</div>
          <div style={{
            marginTop: 14, padding: '10px 12px', borderRadius: 10,
            background: 'rgba(255,255,255,.12)', display: 'grid',
            gridTemplateColumns: 'repeat(4, 1fr)', gap: 6,
          }}>
            {[{l:'LoRa',v:'OK'},{l:'MPU',v:'OK'},{l:'MLX',v:'OK'},{l:'Fila',v:'OK'}].map((c,i)=>(
              <div key={i} style={{display:'flex',flexDirection:'column',alignItems:'center'}}>
                <span style={{fontFamily: RT.mono, fontSize: 10, opacity: .7}}>{c.l}</span>
                <span style={{fontFamily: RT.mono, fontSize: 13, fontWeight: 700}}>{c.v}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Telemetria detalhada */}
        <Card pad={0}>
          <div style={{padding: '14px 16px', borderBottom: `1px solid ${RT.hairSoft}`, display:'flex',alignItems:'center',justifyContent:'space-between'}}>
            <span style={{fontFamily: RT.display, fontSize: 15, fontWeight: 600, color: RT.ink, letterSpacing: '-.01em'}}>Última posição</span>
            <span style={{fontFamily: RT.mono, fontSize: 11, color: RT.inkMute}}>17/04 14:31:08</span>
          </div>
          <div style={{padding: '12px 16px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10}}>
            {[
              {l:'Latitude',v:'−23.2847°', m: true},
              {l:'Longitude',v:'−46.5920°', m: true},
              {l:'GPS fix',v:'8 sat · HDOP 1.2', m: false},
              {l:'RSSI LoRa',v:'−92 dBm', m: true},
            ].map((r,i)=>(
              <div key={i}>
                <div style={{fontFamily: RT.sans, fontSize: 11, color: RT.inkMute, textTransform: 'uppercase', letterSpacing: '.04em'}}>{r.l}</div>
                <div style={{fontFamily: r.m ? RT.mono : RT.sans, fontSize: 14, fontWeight: 600, color: RT.ink}}>{r.v}</div>
              </div>
            ))}
          </div>
        </Card>

        {/* Ações operacionais */}
        <div style={{display: 'flex', flexDirection: 'column', gap: 8}}>
          {[
            {i:'polygon', t:'Configurar Geofence', s:'Desenhar perímetro no mapa', k:'1.6 km²'},
            {i:'route', t:'Plano de Condução', s:'Arrebanhar para área-alvo', k:null},
            {i:'clipboard', t:'Log da coleira', s:'Mensagens recebidas pela matriz', k:'324'},
          ].map((a,i)=>(
            <div key={i} style={{
              padding: '14px 16px', background: RT.bg, border: `1px solid ${RT.hair}`,
              borderRadius: RT.r3, display: 'flex', alignItems: 'center', gap: 14,
            }}>
              <div style={{
                width: 40, height: 40, borderRadius: 10, background: RT.primarySoft,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Icon name={a.i} size={20} color={RT.primaryDeep}/>
              </div>
              <div style={{flex: 1}}>
                <div style={{fontFamily: RT.sans, fontSize: 15, fontWeight: 600, color: RT.ink}}>{a.t}</div>
                <div style={{fontFamily: RT.sans, fontSize: 12, color: RT.inkMute}}>{a.s}</div>
              </div>
              {a.k && <span style={{fontFamily: RT.mono, fontSize: 12, color: RT.inkMute}}>{a.k}</span>}
              <Icon name="chev" size={18} color={RT.inkMute}/>
            </div>
          ))}
        </div>
      </div>
      <NavPill/>
    </div>
  );
}

// ── GEOFENCE ─
function GeofenceScreen() {
  return (
    <div style={{width: '100%', height: '100%', position: 'relative', background: RT.ink}}>
      <MapCanvas variant="night">
        <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice" style={{position: 'absolute', inset: 0}}>
          {/* polígono sendo desenhado */}
          <path d="M 80 300 L 200 260 L 300 310 L 310 420 L 200 460 L 100 420 Z"
                fill="oklch(.62 .14 55 / .18)" stroke="oklch(.72 .15 60)" strokeWidth="2"
                strokeDasharray="5 3"/>
          {/* pontos */}
          {[[80,300],[200,260],[300,310],[310,420],[200,460],[100,420]].map(([x,y],i)=>(
            <g key={i}>
              <circle cx={x} cy={y} r="7" fill="oklch(.72 .15 60)" stroke="#fff" strokeWidth="2"/>
              <text x={x} y={y - 14} fill="#fff" fontFamily="JetBrains Mono" fontSize="10" textAnchor="middle" fontWeight="600">{i+1}</text>
            </g>
          ))}
        </svg>
      </MapCanvas>

      <div style={{position: 'relative', zIndex: 3}}>
        <StatusBar dark/>
        <AppBar title="Geofence · Coleira 042" subtitle="Toque para adicionar vértices" variant="solid" trailing={[{icon:'refresh'},{icon:'more'}]}/>
      </div>

      {/* HUD contador */}
      <div style={{
        position: 'absolute', top: 120, left: '50%', transform: 'translateX(-50%)', zIndex: 3,
        padding: '8px 14px', borderRadius: RT.rFull,
        background: 'rgba(20,30,25,.8)', backdropFilter: 'blur(12px)',
        color: '#fff', fontFamily: RT.mono, fontSize: 13, fontWeight: 600,
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        <span style={{width: 6, height: 6, borderRadius: '50%', background: RT.accent}}/>
        6 / 32 vértices · 1.6 km²
      </div>

      {/* Bottom controls */}
      <div style={{
        position: 'absolute', left: 12, right: 12, bottom: 40, zIndex: 4,
        display: 'flex', flexDirection: 'column', gap: 10,
      }}>
        <div style={{
          padding: 12, borderRadius: RT.r3, background: 'rgba(20,30,25,.8)',
          backdropFilter: 'blur(16px)', display: 'flex', gap: 8,
        }}>
          <button style={{flex: 1, height: 44, borderRadius: 10, background: 'rgba(255,255,255,.08)', color: '#fff', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontFamily: RT.sans, fontWeight: 600, fontSize: 14}}>
            <Icon name="undo" size={17} color="#fff"/>Desfazer
          </button>
          <button style={{flex: 1, height: 44, borderRadius: 10, background: 'rgba(255,255,255,.08)', color: '#fff', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, fontFamily: RT.sans, fontWeight: 600, fontSize: 14}}>
            <Icon name="erase" size={17} color="#fff"/>Limpar
          </button>
        </div>
        <Btn block size="lg" variant="accent" icon="send">Publicar cerca via LoRa</Btn>
      </div>

      <NavPill dark overlay/>
    </div>
  );
}

// ── EVENTS ─
function EventsScreen() {
  const evs = [
    {s:'danger', i:'alert', t:'Coleira fora da geofence', d:'C-042 · Quadrante Norte', ts:'agora', live:true},
    {s:'warn', i:'battery', t:'Bateria baixa', d:'C-017 · 18% restante', ts:'há 12 min'},
    {s:'ok', i:'check', t:'Cerca publicada com sucesso', d:'C-042 · 6 vértices', ts:'há 34 min'},
    {s:'info', i:'gateway', t:'Gateway reconectado', d:'GW-01 · Sede', ts:'há 2h'},
    {s:'ok', i:'route', t:'Arrebanhamento concluído', d:'Lote 3 · 7 animais', ts:'ontem 17:02'},
    {s:'warn', i:'gps', t:'GPS sem fix prolongado', d:'C-088 · 34 min', ts:'ontem 14:40'},
  ];
  const toneMap = {danger: RT.danger, warn: RT.warn, ok: RT.ok, info: RT.info};
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', flexDirection: 'column', background: RT.bgSubtle, position: 'relative'}}>
      <StatusBar/>
      <div style={{padding: '12px 16px 0'}}>
        <div style={{fontFamily: RT.display, fontSize: 28, fontWeight: 700, color: RT.ink, letterSpacing: '-.03em'}}>Eventos</div>
        <div style={{fontFamily: RT.sans, fontSize: 13, color: RT.inkSoft}}>2 críticos · 4 informativos nas últimas 24h</div>
      </div>
      <div style={{padding: '10px 12px 0', display: 'flex', gap: 6, overflowX: 'hidden'}}>
        <Chip active>Todos</Chip>
        <Chip dot={RT.danger}>Críticos</Chip>
        <Chip dot={RT.warn}>Atenção</Chip>
        <Chip>Telemetria</Chip>
      </div>

      <div style={{flex: 1, overflow: 'hidden', padding: '12px', display: 'flex', flexDirection: 'column', gap: 8}}>
        {evs.map((e,i)=>(
          <div key={i} style={{
            padding: '12px 14px', background: RT.bg, border: `1px solid ${RT.hair}`,
            borderRadius: RT.r3, display: 'flex', gap: 12, alignItems: 'flex-start',
            position: 'relative',
          }}>
            <div style={{
              width: 36, height: 36, borderRadius: 10,
              background: `${toneMap[e.s]}1a`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}>
              <Icon name={e.i} size={18} color={toneMap[e.s]}/>
            </div>
            <div style={{flex: 1, minWidth: 0}}>
              <div style={{display: 'flex', alignItems: 'baseline', gap: 8}}>
                <span style={{fontFamily: RT.sans, fontSize: 14, fontWeight: 600, color: RT.ink, flex: 1}}>{e.t}</span>
                {e.live && <Badge tone="danger">● AO VIVO</Badge>}
              </div>
              <div style={{fontFamily: RT.sans, fontSize: 12, color: RT.inkSoft, marginTop: 2}}>{e.d}</div>
              <div style={{fontFamily: RT.mono, fontSize: 10, color: RT.inkMute, marginTop: 4, letterSpacing: '.02em'}}>{e.ts}</div>
            </div>
          </div>
        ))}
      </div>

      <TabBar active="events"/>
      <NavPill/>
    </div>
  );
}

// ── PROFILE / FILTERS ─
function ProfileScreen() {
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', flexDirection: 'column', background: RT.bg, position: 'relative'}}>
      <StatusBar/>
      <div style={{padding: '12px 16px 16px', background: RT.bgSubtle, borderBottom: `1px solid ${RT.hair}`}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 12}}>
          <div style={{
            width: 56, height: 56, borderRadius: 18, background: RT.primaryDeep,
            color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: RT.display, fontSize: 22, fontWeight: 700,
          }}>JR</div>
          <div style={{flex: 1}}>
            <div style={{fontFamily: RT.display, fontSize: 18, fontWeight: 700, color: RT.ink, letterSpacing: '-.02em'}}>João Ribeiro</div>
            <div style={{fontFamily: RT.sans, fontSize: 12, color: RT.inkSoft}}>joao@fazendadoce.com.br</div>
            <Badge tone="primary" style={{marginTop: 4}}>Administrador</Badge>
          </div>
          <button style={{width: 40, height: 40, borderRadius: RT.rFull, background: RT.bg, border: `1px solid ${RT.hair}`, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
            <Icon name="settings" size={18}/>
          </button>
        </div>
      </div>

      <div style={{flex: 1, overflow: 'hidden', padding: 14, display: 'flex', flexDirection: 'column', gap: 14}}>
        <div>
          <div style={{display:'flex',alignItems:'center',justifyContent:'space-between', marginBottom: 8}}>
            <span style={{fontFamily: RT.sans, fontSize: 13, fontWeight: 600, color: RT.inkSoft, textTransform: 'uppercase', letterSpacing: '.06em'}}>Filtros do mapa</span>
            <span style={{fontFamily: RT.mono, fontSize: 11, color: RT.inkMute}}>3 ativos</span>
          </div>
          <Card pad={0}>
            {[
              {i:'pin', l:'Propriedades', v:'Fazenda Doce Vale', n:1, on:true},
              {i:'polygon', l:'Áreas', v:'A2 · Piquete Norte', n:2, on:true},
              {i:'collar', l:'Coleiras', v:'Todas', n:9, on:true},
              {i:'gateway', l:'Gateways', v:'Nenhum', n:0, on:false},
            ].map((f,i,arr)=>(
              <div key={i} style={{
                padding: '14px 14px', display: 'flex', alignItems: 'center', gap: 12,
                borderBottom: i < arr.length - 1 ? `1px solid ${RT.hairSoft}` : 'none',
              }}>
                <div style={{
                  width: 36, height: 36, borderRadius: 10,
                  background: f.on ? RT.primarySoft : RT.hairSoft,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <Icon name={f.i} size={18} color={f.on ? RT.primaryDeep : RT.inkMute}/>
                </div>
                <div style={{flex: 1}}>
                  <div style={{fontFamily: RT.sans, fontSize: 14, fontWeight: 600, color: RT.ink}}>{f.l}</div>
                  <div style={{fontFamily: RT.sans, fontSize: 12, color: RT.inkMute}}>{f.v}</div>
                </div>
                {f.n > 0 && <span style={{fontFamily: RT.mono, fontSize: 12, color: RT.inkMute}}>{f.n}</span>}
                <div style={{
                  width: 42, height: 24, borderRadius: 12, padding: 2,
                  background: f.on ? RT.primary : RT.hair,
                  display: 'flex', alignItems: 'center',
                }}>
                  <div style={{
                    width: 20, height: 20, borderRadius: '50%', background: '#fff',
                    transform: f.on ? 'translateX(18px)' : 'translateX(0)',
                    boxShadow: '0 1px 3px rgba(0,0,0,.2)', transition: 'transform .2s',
                  }}/>
                </div>
              </div>
            ))}
          </Card>
        </div>

        <div>
          <div style={{fontFamily: RT.sans, fontSize: 13, fontWeight: 600, color: RT.inkSoft, textTransform: 'uppercase', letterSpacing: '.06em', marginBottom: 8}}>Conta</div>
          <Card pad={0}>
            {[
              {i:'user', l:'Dados pessoais'},
              {i:'bell', l:'Notificações', v:'Push, LoRa, críticos'},
              {i:'wifi', l:'Sincronização', v:'Última: há 2 min'},
            ].map((a,i,arr) => (
              <div key={i} style={{
                padding: '14px', display: 'flex', alignItems: 'center', gap: 12,
                borderBottom: i < arr.length - 1 ? `1px solid ${RT.hairSoft}` : 'none',
              }}>
                <Icon name={a.i} size={18} color={RT.inkSoft}/>
                <div style={{flex: 1}}>
                  <div style={{fontFamily: RT.sans, fontSize: 14, fontWeight: 500, color: RT.ink}}>{a.l}</div>
                  {a.v && <div style={{fontFamily: RT.sans, fontSize: 12, color: RT.inkMute}}>{a.v}</div>}
                </div>
                <Icon name="chev" size={16} color={RT.inkMute}/>
              </div>
            ))}
          </Card>
        </div>
      </div>
      <TabBar active="profile"/>
      <NavPill/>
    </div>
  );
}

// ── HERDING (Arrebanhamento) ─
function HerdingScreen() {
  return (
    <div style={{width: '100%', height: '100%', position: 'relative', background: RT.bg}}>
      <MapCanvas>
        <svg width="100%" height="100%" viewBox="0 0 390 844" preserveAspectRatio="xMidYMid slice" style={{position: 'absolute', inset: 0}}>
          {/* origem (coleiras espalhadas) */}
          <circle cx="90" cy="240" r="60" fill="oklch(.62 .14 55 / .1)" stroke="oklch(.62 .14 55)" strokeWidth="1" strokeDasharray="3 3"/>
          {/* alvo */}
          <path d="M 220 380 L 320 370 L 340 460 L 280 510 L 210 480 Z"
                fill="oklch(.42 .11 150 / .18)" stroke="oklch(.42 .11 150)" strokeWidth="2.5"/>
          {/* seta de movimento */}
          <path d="M 120 270 Q 180 330 240 420" stroke="oklch(.62 .14 55)" strokeWidth="2.5" fill="none" strokeDasharray="6 4"/>
          <path d="M 232 412 L 244 420 L 236 432" stroke="oklch(.62 .14 55)" strokeWidth="2.5" fill="none"/>
        </svg>
        <Pin x={70} y={220} variant="collar" label="C-017"/>
        <Pin x={110} y={260} variant="collar" label="C-042"/>
        <Pin x={95} y={290} variant="collar" label="C-088"/>
        <div style={{position:'absolute',left:280,top:430,transform:'translate(-50%,-50%)',padding:'4px 8px',background:RT.primaryDeep,color:'#fff',borderRadius:6,fontFamily:RT.mono,fontSize:10,fontWeight:700,boxShadow:RT.sh2}}>ALVO</div>
      </MapCanvas>

      <div style={{position: 'relative', zIndex: 3}}>
        <StatusBar/>
        <AppBar title="Arrebanhamento" subtitle="Etapa 2 de 3 · Selecionar área-alvo"/>
        {/* Stepper */}
        <div style={{padding: '4px 16px 14px', display: 'flex', gap: 6}}>
          {['Coleiras','Área-alvo','Revisar'].map((s,i)=>(
            <div key={i} style={{flex: 1, display: 'flex', flexDirection: 'column', gap: 4}}>
              <div style={{height: 3, borderRadius: 2, background: i <= 1 ? RT.primary : RT.hair}}/>
              <span style={{fontFamily: RT.sans, fontSize: 11, fontWeight: i===1?700:500, color: i<=1?RT.ink:RT.inkMute}}>{s}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Bottom sheet operação */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 28, zIndex: 4,
        background: RT.bg, borderRadius: '20px 20px 0 0',
        boxShadow: '0 -8px 24px rgba(20,30,25,.10)', padding: '12px 0 16px',
      }}>
        <div style={{width: 36, height: 4, borderRadius: 2, background: RT.hair, margin: '0 auto 10px'}}/>
        <div style={{padding: '0 16px 10px'}}>
          <div style={{display:'flex',alignItems:'center',justifyContent:'space-between',marginBottom:8}}>
            <span style={{fontFamily: RT.display, fontSize: 16, fontWeight: 700, color: RT.ink, letterSpacing: '-.01em'}}>3 coleiras selecionadas</span>
            <span style={{fontFamily:RT.mono,fontSize:11,color:RT.inkMute}}>Lote Norte</span>
          </div>
          <div style={{display: 'flex', gap: 6, flexWrap: 'wrap'}}>
            <Chip icon="collar" active>C-017</Chip>
            <Chip icon="collar" active>C-042</Chip>
            <Chip icon="collar" active>C-088</Chip>
          </div>
        </div>
        <div style={{padding: '10px 16px', background: RT.warnSoft, borderTop: `1px solid ${RT.hair}`, borderBottom: `1px solid ${RT.hair}`, display: 'flex', gap: 10, alignItems: 'center'}}>
          <Icon name="alert" size={16} color="oklch(.45 .15 75)"/>
          <span style={{fontFamily: RT.sans, fontSize: 12, color: 'oklch(.35 .12 75)'}}>Confirme antes de publicar — comandos LoRa são irreversíveis</span>
        </div>
        <div style={{padding: '12px 16px 0', display: 'flex', gap: 8}}>
          <Btn variant="ghost" size="md" style={{flex: 1}}>Voltar</Btn>
          <Btn size="md" variant="accent" trailing="arrowR" style={{flex: 2}}>Revisar e publicar</Btn>
        </div>
      </div>
      <NavPill overlay/>
    </div>
  );
}

window.DeviceDetailsScreen = DeviceDetailsScreen;
window.GeofenceScreen = GeofenceScreen;
window.EventsScreen = EventsScreen;
window.ProfileScreen = ProfileScreen;
window.HerdingScreen = HerdingScreen;
