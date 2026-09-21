const http = require("http");
const { URL, URLSearchParams } = require("url");
const { createHmac, createHash, randomBytes, createCipheriv, createDecipheriv, timingSafeEqual } = require("crypto");

const PORT = Number(process.env.PORT || 10000);
const SECRET = process.env.META_BRIDGE_SECRET || "";
const GRAPH_VERSION = "v26.0";
const rate = new Map();

if (SECRET.length < 32) {
  throw new Error("META_BRIDGE_SECRET must be configured with at least 32 characters.");
}

function b64u(input) { return Buffer.from(input).toString("base64url"); }
function jsonB64(value) { return b64u(Buffer.from(JSON.stringify(value))); }
function sign(input) { return createHmac("sha256", SECRET).update(input).digest("base64url"); }
function sessionToken(payload) {
  const body = jsonB64(payload);
  return body + "." + sign(body);
}
function verifySession(token) {
  if (typeof token !== "string" || token.length > 4096) throw new Error("Sessão inválida.");
  const parts = token.split(".");
  if (parts.length !== 2) throw new Error("Sessão inválida.");
  const expected = Buffer.from(sign(parts[0]));
  const actual = Buffer.from(parts[1]);
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) throw new Error("Assinatura da sessão inválida.");
  const value = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  const now = Math.floor(Date.now() / 1000);
  if (!value.exp || value.exp < now || !value.appId || !value.configId) throw new Error("Sessão expirada.");
  return value;
}
const ticketKey = createHash("sha256").update(SECRET + ":quickprint-meta-ticket").digest();
function encryptTicket(value) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", ticketKey, iv);
  const plaintext = Buffer.from(JSON.stringify(value));
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, ciphertext]).toString("base64url");
}
function decryptTicket(token) {
  const raw = Buffer.from(String(token || ""), "base64url");
  if (raw.length < 29 || raw.length > 8192) throw new Error("Ticket inválido.");
  const iv = raw.subarray(0, 12);
  const tag = raw.subarray(12, 28);
  const ciphertext = raw.subarray(28);
  const decipher = createDecipheriv("aes-256-gcm", ticketKey, iv);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  const value = JSON.parse(plain.toString("utf8"));
  if (!value.exp || value.exp < Math.floor(Date.now() / 1000)) throw new Error("Ticket expirado.");
  return value;
}
function safeId(value, max = 64) {
  const v = String(value || "").trim();
  return /^[0-9]{5,64}$/.test(v) && v.length <= max ? v : "";
}
function safeSecret(value) {
  const v = String(value || "").trim();
  return v.length >= 8 && v.length <= 512 ? v : "";
}
function safeCode(value) {
  const v = String(value || "").trim();
  return v.length >= 8 && v.length <= 4096 ? v : "";
}
function allow(req) {
  const ip = String(req.headers["x-forwarded-for"] || req.socket.remoteAddress || "").split(",")[0].trim();
  const now = Date.now();
  const current = rate.get(ip) || { start: now, count: 0 };
  if (now - current.start > 60000) { current.start = now; current.count = 0; }
  current.count += 1;
  rate.set(ip, current);
  return current.count <= 80;
}
function securityHeaders(res) {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
  res.setHeader("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  res.setHeader("Cache-Control", "no-store");
}
function json(res, code, data) {
  securityHeaders(res);
  res.statusCode = code;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(data));
}
function html(res, code, body, connect = false) {
  securityHeaders(res);
  res.statusCode = code;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  if (connect) {
    res.setHeader("Content-Security-Policy",
      "default-src 'none'; script-src 'self' 'unsafe-inline' https://connect.facebook.net; style-src 'unsafe-inline'; img-src 'self' data: https://*.facebook.com https://*.fbcdn.net; connect-src https://graph.facebook.com https://www.facebook.com https://web.facebook.com https://business.facebook.com; frame-src https://www.facebook.com https://web.facebook.com https://business.facebook.com; form-action 'none'; base-uri 'none'; frame-ancestors 'none'");
  } else {
    res.setHeader("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'");
  }
  res.end(body);
}
async function readJson(req) {
  let total = 0; const chunks = [];
  for await (const chunk of req) {
    total += chunk.length;
    if (total > 32768) throw new Error("Requisição grande demais.");
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}
async function graph(path, token, options = {}) {
  const url = path.startsWith("http") ? path : `https://graph.facebook.com/${GRAPH_VERSION}/${path.replace(/^\//, "")}`;
  const headers = { Accept: "application/json", ...(options.headers || {}) };
  if (token) headers.Authorization = "Bearer " + token;
  const response = await fetch(url, { ...options, headers });
  const text = await response.text();
  let body = {};
  try { body = JSON.parse(text); } catch { body = { raw: text.slice(0, 1000) }; }
  if (!response.ok || body.error) {
    const err = new Error(body?.error?.message || `Meta Graph HTTP ${response.status}`);
    err.metaCode = body?.error?.code;
    err.metaSubcode = body?.error?.error_subcode;
    throw err;
  }
  return body;
}
async function exchangeCode(appId, appSecret, code) {
  const params = new URLSearchParams({ client_id: appId, client_secret: appSecret, code });
  const response = await fetch(`https://graph.facebook.com/${GRAPH_VERSION}/oauth/access_token?${params.toString()}`, {
    method: "GET", headers: { Accept: "application/json" }
  });
  const text = await response.text();
  let body = {};
  try { body = JSON.parse(text); } catch { body = { raw: text.slice(0, 1000) }; }
  if (!response.ok || body.error || !body.access_token) {
    throw new Error(body?.error?.message || "A Meta não devolveu um access token.");
  }
  return body;
}
async function resolveAssets({ appId, appSecret, accessToken, wabaId, phoneNumberId, businessId }) {
  let resolvedWaba = safeId(wabaId);
  let resolvedPhone = safeId(phoneNumberId);
  const resolvedBusiness = safeId(businessId);
  let displayPhoneNumber = "";
  let verifiedName = "";
  let wabaName = "";

  if (!resolvedWaba && appSecret) {
    try {
      const debugUrl = `https://graph.facebook.com/${GRAPH_VERSION}/debug_token?input_token=${encodeURIComponent(accessToken)}&access_token=${encodeURIComponent(appId + "|" + appSecret)}`;
      const debug = await graph(debugUrl, "");
      const scopes = Array.isArray(debug?.data?.granular_scopes) ? debug.data.granular_scopes : [];
      const wa = scopes.find(x => x?.scope === "whatsapp_business_management");
      if (Array.isArray(wa?.target_ids) && wa.target_ids.length) resolvedWaba = safeId(wa.target_ids[0]);
    } catch (_) {}
  }

  if (resolvedWaba) {
    try {
      const waba = await graph(`${resolvedWaba}?fields=id,name`, accessToken);
      wabaName = String(waba?.name || "");
    } catch (_) {}
    if (!resolvedPhone) {
      const phones = await graph(`${resolvedWaba}/phone_numbers?fields=id,display_phone_number,verified_name,name_status`, accessToken);
      const first = Array.isArray(phones?.data) ? phones.data[0] : null;
      if (first) {
        resolvedPhone = safeId(first.id);
        displayPhoneNumber = String(first.display_phone_number || "");
        verifiedName = String(first.verified_name || "");
      }
    }
  }

  if (resolvedPhone && (!displayPhoneNumber || !verifiedName)) {
    try {
      const phone = await graph(`${resolvedPhone}?fields=id,display_phone_number,verified_name`, accessToken);
      displayPhoneNumber = displayPhoneNumber || String(phone?.display_phone_number || "");
      verifiedName = verifiedName || String(phone?.verified_name || "");
    } catch (_) {}
  }
  return { wabaId: resolvedWaba, phoneNumberId: resolvedPhone, businessId: resolvedBusiness, displayPhoneNumber, verifiedName, wabaName };
}
function connectPage(session, token) {
  const appId = JSON.stringify(session.appId);
  const configId = JSON.stringify(session.configId);
  const sessionJson = JSON.stringify(token);
  const coexistence = session.coexistence ? "true" : "false";
  return `<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Conectar Meta • Quick Print OS</title>
<style>body{font-family:system-ui,-apple-system,sans-serif;margin:0;background:#0b1220;color:#eef2ff}main{max-width:640px;margin:0 auto;padding:28px 20px}.card{background:#111a2e;border:1px solid #263452;border-radius:20px;padding:22px}h1{margin-top:0}.muted{color:#a8b3cf;line-height:1.5}button{width:100%;border:0;border-radius:12px;padding:14px 18px;font-size:16px;font-weight:700;background:#1877f2;color:#fff}button:disabled{opacity:.55}.status{margin-top:14px;padding:12px;border-radius:10px;background:#0b1324}small{display:block;margin-top:16px;color:#8190b4;line-height:1.5}</style>
</head><body><div id="fb-root"></div><main><div class="card">
<h1>Conectar WhatsApp à Meta</h1>
<p class="muted">Faça login na Meta, escolha ou crie a conta do WhatsApp Business e autorize o Quick Print OS. A credencial final volta diretamente para o aplicativo.</p>
<button id="connect" disabled>Carregando Meta…</button><div class="status" id="status">Preparando conexão segura.</div>
<small>O Quick Print Connect não armazena seu App Secret nem o access token. O token final fica protegido no Android Keystore.</small>
</div></main>
<script>
const SESSION=${sessionJson},APP_ID=${appId},CONFIG_ID=${configId},COEXISTENCE=${coexistence};
let authCode="",directToken="",sessionInfo=null,completing=false;
const statusEl=document.getElementById("status"),button=document.getElementById("connect");
function setStatus(v){statusEl.textContent=v}
function appReturn(params){const q=new URLSearchParams(params);window.location.href="quickprintos://meta-whatsapp-auth?"+q.toString()}
async function finishIfReady(){
 if(completing||!sessionInfo||(!authCode&&!directToken))return;
 completing=true;setStatus("Finalizando autorização e voltando ao Quick Print OS…");
 try{
  const r=await fetch("/browser-complete",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({session:SESSION,code:authCode,accessToken:directToken,wabaId:sessionInfo.waba_id||"",phoneNumberId:sessionInfo.phone_number_id||"",businessId:sessionInfo.business_id||sessionInfo.businessId||""})});
  const data=await r.json();if(!r.ok||!data.ticket)throw new Error(data.error||"Falha ao finalizar.");
  appReturn({status:"success",ticket:data.ticket});
 }catch(e){completing=false;setStatus("Falha: "+(e.message||e))}
}
window.addEventListener("message",function(event){
 const allowed=["https://www.facebook.com","https://web.facebook.com","https://business.facebook.com"];if(!allowed.includes(event.origin))return;
 try{
  const data=typeof event.data==="string"?JSON.parse(event.data):event.data;if(!data||data.type!=="WA_EMBEDDED_SIGNUP")return;
  if(data.event==="FINISH"||data.event==="FINISH_ONLY_WABA"){sessionInfo=data.data||{};setStatus("Conta WhatsApp autorizada. Concluindo…");finishIfReady()}
  else if(data.event==="CANCEL"){appReturn({status:"cancelled"})}
  else if(data.event==="ERROR"){appReturn({status:"error",message:String(data?.data?.error_message||"Erro no Embedded Signup").slice(0,300)})}
 }catch(_){}
});
window.fbAsyncInit=function(){FB.init({appId:APP_ID,cookie:true,xfbml:true,version:"${GRAPH_VERSION}"});button.disabled=false;button.textContent="Entrar com Meta e conectar WhatsApp";setStatus("Pronto para autenticar.")};
button.addEventListener("click",function(){
 setStatus("Abrindo autenticação oficial da Meta…");
 const extras={setup:{}};if(COEXISTENCE)extras.featureType="whatsapp_business_app_onboarding";
 FB.login(function(response){
  if(response&&response.authResponse){authCode=response.authResponse.code||"";directToken=response.authResponse.accessToken||"";finishIfReady()}
  else setStatus("Login cancelado ou não autorizado.");
 },{config_id:CONFIG_ID,auth_type:"rerequest",response_type:"code",override_default_response_type:true,extras:extras});
});
</script><script async defer crossorigin="anonymous" src="https://connect.facebook.net/pt_BR/sdk.js"></script></body></html>`;
}

const server = http.createServer(async (req,res)=>{
 try{
  if(!allow(req))return json(res,429,{error:"Muitas solicitações. Tente novamente em instantes."});
  const url=new URL(req.url,"https://quickprint.local");
  if(req.method==="GET"&&url.pathname==="/health")return json(res,200,{ok:true,service:"quickprint-meta-connect",graph:GRAPH_VERSION});
  if(req.method==="POST"&&url.pathname==="/session"){
   const body=await readJson(req),appId=safeId(body.appId,32),configId=safeId(body.configId,64);
   if(!appId||!configId)return json(res,400,{error:"App ID ou Configuration ID inválido."});
   const now=Math.floor(Date.now()/1000);
   const token=sessionToken({appId,configId,coexistence:body.coexistence!==false,nonce:randomBytes(16).toString("base64url"),iat:now,exp:now+900});
   const base=String(process.env.PUBLIC_BASE_URL||"").replace(/\/$/,"");
   if(!base.startsWith("https://"))return json(res,503,{error:"PUBLIC_BASE_URL não configurada."});
   return json(res,200,{session:token,authUrl:base+"/connect?session="+encodeURIComponent(token),expiresIn:900});
  }
  if(req.method==="GET"&&url.pathname==="/connect"){
   const token=String(url.searchParams.get("session")||"");
   try{return html(res,200,connectPage(verifySession(token),token),true)}
   catch(e){return html(res,400,"<h1>Sessão inválida ou expirada</h1><p>Volte ao Quick Print OS e inicie a conexão novamente.</p>")}
  }
  if(req.method==="POST"&&url.pathname==="/browser-complete"){
   const body=await readJson(req),session=verifySession(String(body.session||"")),code=safeCode(body.code),accessToken=safeCode(body.accessToken);
   if(!code&&!accessToken)return json(res,400,{error:"A Meta não devolveu código nem token."});
   const now=Math.floor(Date.now()/1000);
   const ticket=encryptTicket({appId:session.appId,code,accessToken,wabaId:safeId(body.wabaId),phoneNumberId:safeId(body.phoneNumberId),businessId:safeId(body.businessId),iat:now,exp:now+300});
   return json(res,200,{ticket,expiresIn:300});
  }
  if(req.method==="POST"&&url.pathname==="/exchange"){
   const body=await readJson(req),ticket=decryptTicket(String(body.ticket||"")),appSecret=safeSecret(body.appSecret);
   let accessToken=safeCode(ticket.accessToken),expiresIn=null;
   if(!accessToken){
    if(!appSecret)return json(res,400,{error:"App Secret necessário para trocar o código de autorização."});
    const exchanged=await exchangeCode(ticket.appId,appSecret,ticket.code);accessToken=safeCode(exchanged.access_token);expiresIn=Number(exchanged.expires_in||0)||null;
   }
   if(!accessToken)return json(res,502,{error:"Token Meta inválido."});
   const assets=await resolveAssets({appId:ticket.appId,appSecret,accessToken,wabaId:ticket.wabaId,phoneNumberId:ticket.phoneNumberId,businessId:ticket.businessId});
   return json(res,200,{accessToken,tokenType:"bearer",expiresIn,graphVersion:GRAPH_VERSION,...assets});
  }
  if(req.method==="GET"&&url.pathname==="/privacy")return html(res,200,"<main><h1>Privacidade • Quick Print Meta Connect</h1><p>Este serviço atua apenas como ponte temporária para o Embedded Signup da Meta. App Secret e access token não são persistidos pelo serviço. A credencial final é armazenada pelo Quick Print OS no Android Keystore.</p></main>");
  if(req.method==="GET"&&url.pathname==="/terms")return html(res,200,"<main><h1>Termos • Quick Print Meta Connect</h1><p>Use este serviço somente para conectar contas Meta e WhatsApp Business que você está autorizado a administrar.</p></main>");
  if(req.method==="GET"&&url.pathname==="/data-deletion")return html(res,200,"<main><h1>Exclusão de dados</h1><p>O serviço não mantém App Secret ou access token. Sessões são tickets criptográficos com expiração curta e não exigem solicitação de exclusão.</p></main>");
  return json(res,404,{error:"not_found"});
 }catch(e){return json(res,500,{error:String(e&&e.message||"Erro interno").slice(0,500)})}
});
server.listen(PORT,"0.0.0.0",()=>console.log("Quick Print Meta Connect listening on port",PORT));