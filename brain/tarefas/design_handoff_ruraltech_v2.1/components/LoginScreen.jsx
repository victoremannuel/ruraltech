// Login Screen — redesenhada
function LoginScreen() {
  return (
    <div style={{width: '100%', height: '100%', display: 'flex', flexDirection: 'column', background: RT.bg, position: 'relative'}}>
      <StatusBar/>
      {/* hero block */}
      <div style={{
        height: 340, position: 'relative', overflow: 'hidden',
        background: `linear-gradient(160deg, ${RT.primaryDeep} 0%, oklch(.32 .08 145) 100%)`,
      }}>
        <svg width="100%" height="100%" viewBox="0 0 390 340" preserveAspectRatio="xMidYMid slice" style={{position: 'absolute', inset: 0}}>
          <defs>
            <pattern id="topo" x="0" y="0" width="80" height="80" patternUnits="userSpaceOnUse">
              <path d="M0 40 Q20 20 40 40 T80 40" stroke="rgba(255,255,255,.08)" fill="none" strokeWidth=".8"/>
              <path d="M0 20 Q20 0 40 20 T80 20" stroke="rgba(255,255,255,.05)" fill="none" strokeWidth=".8"/>
              <path d="M0 60 Q20 40 40 60 T80 60" stroke="rgba(255,255,255,.05)" fill="none" strokeWidth=".8"/>
            </pattern>
          </defs>
          <rect width="390" height="340" fill="url(#topo)"/>
          {/* polygon shape */}
          <path d="M 60 180 L 150 140 L 230 170 L 280 230 L 200 280 L 100 260 Z"
                fill="rgba(232,140,60,.15)" stroke="oklch(.72 .12 60)" strokeWidth="1.5" strokeDasharray="3 3"/>
          {/* pins */}
          <circle cx="150" cy="175" r="5" fill="oklch(.85 .15 75)"/>
          <circle cx="150" cy="175" r="12" fill="oklch(.85 .15 75)" opacity=".2"/>
          <circle cx="210" cy="220" r="4" fill="#fff"/>
          <circle cx="115" cy="230" r="4" fill="#fff"/>
        </svg>
        <div style={{position: 'absolute', top: 56, left: 24, display: 'flex', alignItems: 'center', gap: 10}}>
          <div style={{
            width: 40, height: 40, borderRadius: 12, background: 'rgba(255,255,255,.12)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            border: '1px solid rgba(255,255,255,.2)',
          }}>
            <Icon name="logo" size={22} color="#fff" stroke={2}/>
          </div>
          <div style={{
            fontFamily: RT.display, fontSize: 20, fontWeight: 700, color: '#fff',
            letterSpacing: '-.02em',
          }}>RuralTech</div>
        </div>
      </div>

      {/* form */}
      <div style={{
        flex: 1, background: RT.bg, borderRadius: '28px 28px 0 0',
        marginTop: -28, padding: '28px 24px 24px', position: 'relative', zIndex: 2,
        display: 'flex', flexDirection: 'column', gap: 18,
      }}>
        <div>
          <h1 style={{
            fontFamily: RT.display, fontSize: 26, fontWeight: 700,
            color: RT.ink, margin: 0, letterSpacing: '-.03em',
          }}>Entrar na operação</h1>
          <p style={{
            fontFamily: RT.sans, fontSize: 14, color: RT.inkSoft, margin: '4px 0 0',
            lineHeight: 1.4,
          }}>Monitore propriedades, coleiras e gateways em campo.</p>
        </div>

        <div style={{display: 'flex', flexDirection: 'column', gap: 14}}>
          <Field label="E-mail" icon="mail" placeholder="voce@fazenda.com.br" value="joao@fazendadoce.com.br"/>
          <Field label="Senha" icon="lock" type="password" value="••••••••••" trailing="eye"/>
        </div>

        <div style={{display: 'flex', justifyContent: 'flex-end'}}>
          <a style={{fontFamily: RT.sans, fontSize: 13, fontWeight: 500, color: RT.primaryDeep}}>Esqueci minha senha</a>
        </div>

        <Btn block size="lg" trailing="arrowR">Entrar</Btn>
        <Btn block variant="ghost" size="lg">Criar conta</Btn>

        <div style={{
          marginTop: 'auto', padding: '14px 16px', background: RT.bgSubtle,
          borderRadius: RT.r3, border: `1px solid ${RT.hair}`,
          display: 'flex', alignItems: 'center', gap: 12,
        }}>
          <Icon name="wifi" size={18} color={RT.primaryDeep}/>
          <div style={{flex: 1}}>
            <div style={{fontFamily: RT.sans, fontSize: 12, fontWeight: 600, color: RT.ink}}>
              Modo offline disponível
            </div>
            <div style={{fontFamily: RT.sans, fontSize: 11, color: RT.inkMute}}>
              Sincroniza quando recuperar sinal LoRa/celular
            </div>
          </div>
        </div>
      </div>
      <NavPill overlay/>
    </div>
  );
}

window.LoginScreen = LoginScreen;
