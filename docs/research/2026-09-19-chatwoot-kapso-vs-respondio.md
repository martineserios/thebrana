# Research: Chatwoot + Kapso + servicios propios vs respond.io

> **Origen:** cliente de concesionaria automotriz (post-venta, 4 números WhatsApp por área)
> **Fecha:** 2026-09-19 | **Estrategia:** evaluate | **Decisión del proyecto origen:** respond.io se mantiene (2026-09-20)
> **Propósito de esta copia:** reuso en futuros proyectos que evalúen reemplazar respond.io por
> Chatwoot, Kapso o un stack propio. Las secciones 4–10 son el análisis original con contexto
> del cliente; lo transferible está resumido acá arriba.

## Reuso: lo que vale para cualquier proyecto

| Hecho verificado (2026-09-19) | Consecuencia de diseño |
|---|---|
| Chatwoot descarta respuestas de WhatsApp Flows (`nfm_reply` → content null). Issue #13970 abierto desde 2026-04. | Si se usan Flows con Chatwoot, o se parchea Chatwoot (self-hosted, fix pequeño en el parser) o las respuestas van a un servicio propio. Falla en silencio: peligroso. |
| Chatwoot ya envía campañas WhatsApp en lotes de 100 (PR #15867). | El gap de broadcast vs respond.io está mayormente cerrado. |
| Chatwoot Agent Bots: conversación nace `pending`, bot responde vía API, `open` = handoff, agente devuelve a `pending`. Webhooks firmados. | Es el punto de enganche natural para un agente propio (LangGraph etc.). No hace falta flow builder. |
| Chatwoot Dashboard Apps: iframe en el sidebar de la conversación. | Mostrar datos del ERP/CRM al agente humano sin integrar nada más. respond.io no tiene equivalente. |
| `WHATSAPP_CLOUD_BASE_URL` en Chatwoot self-hosted es **global por instalación**. | Un proxy (Kapso u otro BSP) aplica a todos los inboxes WhatsApp. No sirve si la instalación es multi-cliente. |
| Kapso reenvía payload crudo de Meta (idempotency key + HMAC) y expone proxy compatible con Cloud API en `api.kapso.ai/meta/whatsapp`. | Kapso → Chatwoot no necesita traductor. Kapso como transporte es viable sin bridge. |
| Kapso pricing: Free 1 número/2k msgs; Pro USD 25, **3 números**, 100k msgs; Platform USD 299, 50 números, 1M msgs. Meta al costo. | El salto de 3 a 4 números multiplica el costo ×12. Contar números antes de asumir que Kapso es barato. |
| Meta entrega webhooks a **una URL por app**. | Solo un consumidor directo. Si hay inbox + servicio propio, uno reenvía al otro o un BSP hace fan-out. |
| respond.io: Starter 79 / Growth 159 / Advanced 279, por contacto activo mensual. HTTP Request step requiere Advanced. | El patrón somos_mirada (agentes + HTTP Request) cuesta 279+ como piso. |
| Ley 25.326 art. 12 + Disp. 60-E/2016: EE.UU. y Brasil no son "adecuados". | Self-hosting en GCP/AWS sigue siendo transferencia internacional. Cambia el encargado, no la regla. Cláusulas tipo con cada proveedor en todas las opciones. |

**Regla de arquitectura que salió de esto:** un inbox, una conexión a Meta, un dueño del
handoff. Cualquier diseño con dos inboxes vivos (p. ej. Kapso + Chatwoot) necesita un bridge
propio en el camino crítico y no vale la pena salvo requisito concreto.

**Cuándo Chatwoot + servicio propio le gana a respond.io:** hay alguien que va a ser dueño de
un servicio hosteado y de un agente propio a largo plazo, se quiere RAG y datos propios, y el
volumen de contactos hace caro el precio por MAC. **Cuándo respond.io gana:** cero-ops es
prioridad, broadcasts desde el día uno, o la cuenta y el equipo ya están.

---

## 1. Resumen ejecutivo

respond.io empaqueta cuatro cosas: inbox, transporte WhatsApp, automatización e IA. La
alternativa las separa: **Chatwoot** (inbox), **Kapso o Meta directo** (transporte),
**servicio propio** (automatización + agente + RAG). Cada pieza queda igual o mejor que la
de respond.io, a cambio de más build y de operar infraestructura.

Hallazgos que cambian el cálculo respecto a la intuición inicial:

| Hallazgo | Impacto |
|---|---|
| Kapso Pro (USD 25/mes) incluye hasta **3 números**; el cliente tiene **4** → plan Platform USD 299/mes | Kapso deja de ser barato. Compite con respond.io Advanced (USD 279). |
| Chatwoot **descarta las respuestas de WhatsApp Flows** (`nfm_reply` → content null), issue abierto | Las respuestas de Flows deben llegar al servicio propio, no vía Chatwoot. |
| Chatwoot **ya envía campañas de WhatsApp** en lotes de 100 (PR mergeado 2026) | El gap de broadcast se cerró en gran parte. Menos motivo para Kapso. |
| Kapso puede **reenviar el payload crudo de Meta** con clave de idempotencia | Kapso → Chatwoot no necesita traductor. |
| Chatwoot self-hosted acepta `WHATSAPP_CLOUD_BASE_URL` (global por instalación) | Salida Chatwoot → proxy Kapso es posible sin código. |

**Conclusión provisoria:** si se va por Chatwoot, la variante más simple y barata es
**Chatwoot conectado directo a Meta + servicio propio**, sin Kapso. Kapso solo se justifica
si se valoran sus Flows, salud de números y workflows por encima de USD 274/mes extra
respecto al plan Pro (o si el cliente consolida a 3 números).

---

## 2. Posicionamiento

- **respond.io**: SaaS gestionado, "messaging-operations center". Precio por contacto
  activo mensual (MAC). Starter USD 79; Growth USD 159 (automatización, broadcasts, AI
  Agents); Advanced USD 279 (HTTP Request step, requisito del patrón somos_mirada). Tarifas
  de conversación de Meta aparte.
- **Chatwoot**: open source, self-hosted gratis o Chatwoot Cloud por asiento. Inbox de
  soporte primero, messaging-ops segundo. Agent Bots para traer tu propio agente.
- **Kapso**: BSP oficial de Meta para desarrolladores. Embedded Signup, proxy compatible con
  Cloud API, templates, broadcasts, WhatsApp Flows, workflows con código propio, inbox
  propio con rol `human_agent`, observabilidad de números.

---

## 3. Mapa de capacidades (sin n8n, sin Baileys)

| Capacidad respond.io | Cómo se logra | Veredicto |
|---|---|---|
| Inbox unificado para 4 números | Chatwoot, un inbox WhatsApp por número, un team por área | Igual o mejor |
| Flow Builder | Servicio propio: pasos determinísticos en código, LLM solo donde hace falta entender lenguaje | Mejor (versionado, testeable) |
| AI Agents (calificar, rutear, escalar) | Mismo servicio con LangGraph o similar; tools contra Tango y Postgres propio; RAG en pgvector sobre manuales y términos de garantía | Mejor (RAG y datos propios) |
| Handoff a humano | Chatwoot Agent Bot: conversación nace `pending`, bot responde vía API, pasa a `open` para escalar; agente puede devolver a `pending` | Igual |
| Broadcasts y recordatorios | Chatwoot Campaigns (WhatsApp, lotes de 100) para envíos masivos; job propio (Cloud Run Jobs / ECS) para recordatorios individuales con templates | Igual |
| WhatsApp Flows (formularios en chat) | Enviar desde servicio propio vía Cloud API; **recibir respuesta en servicio propio**, no en Chatwoot (ver §5) | Mejor que respond.io, con trabajo |
| Templates y salud de número | Meta Business Manager directo, o Kapso si se lo incluye | Igual |
| CRM de contactos y campos custom | Contactos Chatwoot con custom attributes espejados desde Postgres propio (fuente de verdad) | Igual |
| Reportes, SLA, CSAT | Chatwoot nativo | Igual o mejor |
| Agente ve datos del vehículo/caso | Chatwoot Dashboard Apps: iframe en el sidebar servido por el servicio propio desde Tango | Mejor (respond.io no tiene equivalente) |
| Canales no-WhatsApp | Chatwoot nativo (IG, Messenger, email, web) | Igual |
| Zapier / Make | Webhooks de Chatwoot + endpoints propios | No necesario |

---

## 4. Arquitectura propuesta

### 4a. Variante recomendada: Chatwoot directo a Meta (sin Kapso)

```
  WhatsApp user ──────────► Meta Cloud API (WABA del cliente, 4 números)
  (4 números)                      │ webhook por número
                                   ▼
                          ┌──────────────────────────────┐
                          │ Chatwoot (self-hosted)       │
                          │ inbox · teams · SLA · CSAT   │
                          │ campaigns · labels · reports │
                          └──────┬───────────────▲───────┘
                 agent-bot event │               │ reply / handoff / attrs
                                 ▼               │
   ┌─────────────────────────────────────────────┴───────────────────┐
   │ SERVICIOS PROPIOS (GCP o AWS)                                   │
   │ ┌────────────────┐ ┌───────────────┐ ┌───────────────────────┐  │
   │ │ Agent service  │ │ Jobs          │ │ Datos                 │  │
   │ │ LangGraph/RAG  │ │ recordatorios │ │ Postgres + pgvector   │  │
   │ │ tools → Tango  │ │ vencimientos  │ │ contactos, vehículos, │  │
   │ │ Flows → Meta   │ │ seguimientos  │ │ casos, corpus RAG     │  │
   │ └────────────────┘ └───────────────┘ └───────────────────────┘  │
   └─────────────────────────────────────────────────────────────────┘
```

Problema a resolver: Meta entrega webhooks a **una sola URL por app**. Si Chatwoot la
ocupa, el servicio propio no recibe respuestas de Flows (que Chatwoot descarta). Opciones:
1. **Parchear Chatwoot** (es self-hosted, Ruby): parsear `nfm_reply.response_json` y
   exponerlo en `content_attributes` + webhook saliente. Issue #13970 ya propone el fix.
   Pequeño, y aporta upstream.
2. Servicio propio como receptor del webhook de Meta, reenviando bytes crudos a
   `/webhooks/whatsapp/{phone_number}` de Chatwoot. Simple pero pone al servicio en el
   camino crítico de entrega.

Preferencia: opción 1.

### 4b. Variante con Kapso como transporte

```
  WhatsApp user ──► Kapso (BSP) ──raw Meta payload──► Chatwoot /webhooks/whatsapp/{n}
                      │  ▲                              │
                      │  └── proxy api.kapso.ai/meta ───┘ (WHATSAPP_CLOUD_BASE_URL)
                      └──── eventos Kapso ────────────► Agent service (Flows, etc.)
```

Ventajas: Embedded Signup hosteado, Flows y templates con UI, salud de números, fan-out a
dos consumidores (Chatwoot + servicio) sin código. Costo: USD 299/mes por 4 números.

### 4c. Variante solo Kapso (sin Chatwoot)

Kapso workflows + agentes Kapso + inbox Kapso. Un solo vendor. Pierde madurez de inbox
(reportes, SLA, macros) y canales no-WhatsApp. Válida si el equipo de post-venta es chico
y no necesita reporting.

---

## 5. Validado y abierto

**Validado por investigación (2026-09-19):**
- Kapso reenvía payload crudo de Meta (header `X-Idempotency-Key`, firma HMAC). Chatwoot
  recibe en `/webhooks/whatsapp/{phone_number}`.
- Chatwoot descarta `nfm_reply` (respuestas de Flows). Issue #13970, abierto desde abril
  2026. Templates interactivos también con bugs abiertos (#13267, #12900).
- Chatwoot envía campañas WhatsApp en lotes (PR #15867, mergeado 2026).
- `WHATSAPP_CLOUD_BASE_URL` es global por instalación de Chatwoot.
- Kapso: Free 1 número / 2k msgs; Pro USD 25, 3 números, 100k msgs; Platform USD 299,
  50 números, 1M msgs. Tarifas Meta al costo.
- Chatwoot Agent Bots: webhooks firmados, `pending` ↔ `open`, `conversation_status_changed`
  llega al bot.

**Abierto — requiere spike con cuentas (no hay credenciales en el repo):**
1. **Kapso → Chatwoot inbound.** Un número, Embedded Signup vía Kapso, reenvío crudo a
   Chatwoot. Enviar texto + foto desde un teléfono. ¿Aparecen en el inbox? ¿Chatwoot exige
   el handshake de verify-token en POST? Y salida: ¿el proxy de Kapso acepta las llamadas de
   Chatwoot sin `phoneNumberId` explícito? **Si falla, Kapso queda afuera → variante 4a.**
2. **Doble entrega.** ¿Kapso entrega el mismo evento a Chatwoot y al servicio propio sin
   duplicados? (Solo aplica a 4b.)
3. **Round trip Agent Bot.** Servicio mínimo en Cloud Run: recibe `pending`, responde vía
   API, pasa a `open`, agente devuelve a `pending`. Medir latencia con LLM en el loop y
   pérdida de eventos en cold start.
4. **Template desde job.** Enviar template aprobado desde un job programado y verificar que
   el mensaje saliente cae en la conversación correcta de Chatwoot, no huérfano.
5. **Realidad Meta.** Estado de verificación de Meta Business del cliente; ¿4 números bajo una
   WABA? Gatea todo. Puede que `t-5` ya tenga parte hecho.

---

## 6. Despliegue de referencia (GCP; AWS entre paréntesis)

- **Agent service:** Cloud Run (ECS Fargate). Recibe webhooks de Agent Bot y respuestas de
  Flows. Stateless, scale to zero.
- **Cola delante:** Cloud Tasks o Pub/Sub (SQS). Ack rápido, procesar async — una llamada
  al LLM nunca bloquea la entrega.
- **Jobs:** Cloud Run Jobs + Cloud Scheduler (EventBridge + ECS tasks). Recordatorios de
  service, vencimiento de garantía, seguimiento post-reclamo.
- **Datos:** Cloud SQL Postgres + pgvector (RDS). Contactos, vehículos, casos, resúmenes de
  conversación, chunks RAG. Tango sigue siendo sistema de registro; Postgres es la memoria
  de trabajo del agente.
- **Chatwoot:** Cloud Run o VM chica + Cloud SQL + Memorystore Redis (ECS + RDS +
  ElastiCache). Chatwoot Cloud es alternativa pero pierde `WHATSAPP_CLOUD_BASE_URL` y el
  parche de Flows.
- **Secretos:** Secret Manager. **Observabilidad:** Cloud Logging + Langfuse o LangSmith;
  conversation ID de Chatwoot como clave de correlación.

---

## 7. Costos (orden de magnitud, USD/mes, sin tarifas Meta)

| Opción | Plataforma | Infra propia | Total aprox. |
|---|---|---|---|
| respond.io Advanced (requerido por HTTP Request step) | 279 + MAC | 0 | 279+ |
| Chatwoot self-hosted + servicio propio (4a) | 0 | ~80–150 (Cloud SQL, Run, Redis) | 80–150 |
| Chatwoot Cloud + servicio propio | ~19–39/asiento | ~40–80 (Run, SQL) | depende de asientos |
| Chatwoot + Kapso Platform (4b) | 299 | ~80–150 | 380–450 |
| Kapso Platform solo (4c) | 299 | ~40 (servicio) | ~340 |

Kapso Pro (USD 25) solo aplica si el cliente opera con ≤3 números. Cifras de infra son
estimaciones, no cotizaciones.

---

## 8. Riesgos

- **Operar Chatwoot.** Rails + Postgres + Redis + Sidekiq, upgrades, backups. Necesita
  dueño. Chatwoot Cloud lo elimina a cambio de perder el parche de Flows.
- **Flows en Chatwoot.** Sin parche, las respuestas se pierden en silencio. Es el bug más
  peligroso porque no falla ruidosamente.
- **Dos inboxes** (si se usa Kapso con su inbox activo). Regla: un inbox, una conexión Meta,
  un dueño del handoff. Desactivar el inbox de Kapso si Chatwoot es el inbox.
- **Vendors jóvenes.** Kapso cambia API seguido. Chatwoot es estable pero su capa WhatsApp
  tiene bugs abiertos.
- **Reversión de decisión.** respond.io ya está comprometido en PROJECT.md. Cambiar es
  arquitectura, no tooling.

---

## 9. Datos personales (Argentina)

Ley 25.326 art. 12 prohíbe transferir datos a países sin nivel adecuado de protección
(EE.UU. no lo tiene) salvo consentimiento expreso del titular o cláusulas contractuales
tipo (Disposición 60-E/2016, Res. AAIP 159/2018 y 198/2023). Implicancias:
- Los datos ya viajan a Meta (EE.UU.) por WhatsApp; el consentimiento del cliente al usar el
  canal cubre esa parte en la práctica habitual, pero conviene términos explícitos.
- Chatwoot self-hosted en `southamerica-east1` (GCP São Paulo) o `sa-east-1` (AWS) no es
  Argentina ni país "adecuado" según AAIP; sigue siendo transferencia internacional. Lo que
  cambia es quién es el encargado: el propio cliente vs respond.io/Kapso como terceros.
- **Esto es una pregunta legal, no de ingeniería.** Registrar la base ante AAIP y firmar
  cláusulas tipo con cada proveedor aplica en cualquiera de las opciones.

---

## 10. Próximo paso sugerido

Si la exploración avanza: spike 1 y 3 primero (una tarde cada uno). Si el spike 1 falla o
el cliente no consolida a 3 números, descartar Kapso y quedarse con la variante 4a. Recién
después, ADR `t-7`-style comparando 4a contra respond.io con números reales de MAC.

---

## Fuentes

- respond.io pricing 2026: https://chatarmin.com/en/blog/respond-io-pricing
- Chatwoot vs respond.io: https://www.g2.com/compare/chatwoot-vs-respond-io
- Chatwoot Agent Bots: https://www.chatwoot.com/hc/user-guide/articles/1677497472-how-to-use-agent-bots
- Chatwoot Agent Bots feature: https://www.chatwoot.com/features/chatbots
- Chatwoot env vars: https://developers.chatwoot.com/self-hosted/configuration/environment-variables
- Chatwoot custom WhatsApp URL (PR 5142): https://github.com/chatwoot/chatwoot/pull/5142
- Chatwoot WhatsApp manual setup: https://www.chatwoot.com/hc/user-guide/articles/1756799850-how-to-setup-a-whats_app-channel-manual-flow
- Chatwoot Embedded Signup: https://developers.chatwoot.com/self-hosted/configuration/features/integrations/whatsapp-embedded-signup
- Chatwoot Flows dropped (issue 13970): https://github.com/chatwoot/chatwoot/issues/13970
- Chatwoot Flow send error (issue 13267): https://github.com/chatwoot/chatwoot/issues/13267
- Chatwoot interactive send bug (issue 12900): https://github.com/chatwoot/chatwoot/issues/12900
- Chatwoot WhatsApp campaign batching (PR 15867): https://github.com/chatwoot/chatwoot/pull/15867
- Chatwoot campaigns blog: https://www.chatwoot.com/blog/whatsapp-campaigns-and-workflow-improvements
- Chatwoot changelog: https://www.chatwoot.com/changelog
- Kapso platform: https://kapso.com/platform
- Kapso pricing: https://kapso.com/pricing · https://docs.kapso.ai/docs/whatsapp/pricing-faq
- Kapso webhooks: https://docs.kapso.ai/docs/platform/webhooks/overview
- Kapso Cloud API client / proxy: https://github.com/gokapso/whatsapp-cloud-api-js
- Kapso Chat SDK adapter: https://chat-sdk.dev/adapters/vendor-official/kapso
- Kapso human handoff: https://kapso.com/whatsapp-human-handoff
- Kapso docs, for your team: https://docs.kapso.ai/docs/platform/for-your-team
- AAIP transferencias internacionales: https://www.argentina.gob.ar/transferencias-internacionales
- Ley 25.326 (texto): https://www.oas.org/juridico/pdfs/arg_ley25326.pdf
- Estudio Lexar, transferencia internacional: https://estudiolexar.com/transferencia-internacional-de-datos-personales-desde-argentina/
