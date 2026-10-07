"use client";
import {useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

const roleOptions=["owner","manager","cashier","waiter","stockkeeper","analyst"];
const roleLabel:Record<string,string>={owner:"Proprietário",manager:"Gerente",cashier:"Caixa",waiter:"Atendente",stockkeeper:"Estoque",analyst:"Analista"};
type Member={business_id:string;user_id:string;role:string;active:boolean;created_at:string;profile?:{full_name:string|null;phone:string|null}|null;email:string|null;confirmedAt:string|null;lastSignInAt:string|null};

export default function Funcionarios(){
  const [business,setBusiness]=useState(""),[members,setMembers]=useState<Member[]>([]),[email,setEmail]=useState(""),[fullName,setFullName]=useState(""),[phone,setPhone]=useState(""),[role,setRole]=useState("cashier"),[message,setMessage]=useState(""),[loading,setLoading]=useState(true),[sending,setSending]=useState(false),[actionLink,setActionLink]=useState("");
  async function load(){
    setLoading(true);
    const c=createClient(),{data:{user}}=await c.auth.getUser();
    if(!user){setLoading(false);return}
    const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m){setLoading(false);return}
    setBusiness(m.business_id);
    const r=await fetch(`/api/employees?businessId=${encodeURIComponent(m.business_id)}`);
    const data=await r.json();
    if(!r.ok){setMessage(data.error||"Não foi possível carregar a equipe");setMembers([])}else setMembers(data.members||[]);
    setLoading(false);
  }
  useEffect(()=>{load()},[]);
  async function call(action:string,extra:Record<string,unknown>={}):Promise<boolean>{
    setMessage("");setActionLink("");
    const r=await fetch("/api/employees",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({action,businessId:business,...extra})});
    const data=await r.json();
    if(!r.ok){setMessage(data.error||"Não foi possível concluir a operação");return false}
    if(action==="invite")setMessage("Convite enviado e funcionário criado.");
    else if(action==="remove")setMessage("Acesso removido. O histórico operacional foi preservado.");
    else if(action==="reset"){setMessage("Link de recuperação gerado. Abra-o e entregue ao colaborador por um canal seguro.");setActionLink(data.actionLink||"")}
    else if(action==="resend_invite")setMessage("Convite reenviado.");
    await load();
    return true;
  }
  async function invite(){setSending(true);const ok=await call("invite",{email,fullName,phone,role});if(ok){setEmail("");setFullName("");setPhone("")}setSending(false)}
  const updateMember=async(m:Member,nextRole:string,nextActive:boolean)=>call("update",{userId:m.user_id,role:nextRole,active:nextActive});
  return <div className="main">
    <div className="topbar"><div><h1 className="title">Funcionários</h1><p className="subtitle">Equipe, cargos, convites e recuperação de acesso</p></div><Link href="/dashboard" className="btn" style={{width:"auto",textDecoration:"none"}}>Dashboard</Link></div>
    <div className="card section"><h2>Convidar colaborador</h2>
      <div className="grid" style={{gridTemplateColumns:"repeat(4,minmax(0,1fr))"}}>
        <label className="field"><span>Nome</span><input value={fullName} onChange={e=>setFullName(e.target.value)} placeholder="Nome completo"/></label>
        <label className="field"><span>E-mail</span><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="colaborador@email.com"/></label>
        <label className="field"><span>Telefone</span><input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="+598 ..."/></label>
        <label className="field"><span>Cargo</span><select value={role} onChange={e=>setRole(e.target.value)}>{roleOptions.map(r=><option key={r} value={r}>{roleLabel[r]}</option>)}</select></label>
      </div>
      <button className="btn" onClick={invite} disabled={!business||!fullName||!email||sending}>{sending?"Enviando...":"Enviar convite"}</button>
      {message&&<div className="notice">{message}</div>}
      {actionLink&&<button className="btn" style={{width:"auto",marginTop:10}} onClick={()=>window.open(actionLink,"_blank","noopener,noreferrer")}>Abrir link de recuperação</button>}
    </div>
    <div className="section"><h2>Equipe cadastrada</h2>
      {loading?<div className="card">Carregando...</div>:<div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Nome</th><th>E-mail</th><th>Cargo</th><th>Acesso</th><th>Último acesso</th><th>Ações</th></tr></thead><tbody>
        {members.map(m=>{
          const profile=m.profile;
          const isOwner=m.role==="owner";
          return <tr key={m.user_id}>
            <td>{profile?.full_name||"Sem nome"}<div style={{fontSize:12,opacity:.7}}>{profile?.phone||"Sem telefone"}</div></td>
            <td>{m.email||"—"}</td>
            <td><select value={m.role} disabled={isOwner} onChange={e=>updateMember(m,e.target.value,m.active)}>{roleOptions.map(r=><option key={r} value={r}>{roleLabel[r]}</option>)}</select></td>
            <td>{m.active?"Ativo":"Inativo"} · {m.confirmedAt?"Confirmado":"Convite pendente"}</td>
            <td>{m.lastSignInAt?new Date(m.lastSignInAt).toLocaleString("es-UY"):"Nunca"}</td>
            <td><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>
              <button className="btn" style={{width:"auto"}} onClick={()=>updateMember(m,m.role,!m.active)}>{m.active?"Desativar":"Ativar"}</button>
              {!m.confirmedAt&&<button className="btn" style={{width:"auto"}} onClick={()=>call("resend_invite",{userId:m.user_id})}>Reenviar convite</button>}
              <button className="btn" style={{width:"auto"}} onClick={()=>call("reset",{userId:m.user_id})}>Redefinir senha</button>
              {m.active&&<button className="btn" style={{width:"auto"}} onClick={()=>call("remove",{userId:m.user_id})}>Remover acesso</button>}
            </div></td>
          </tr>
        })}
      </tbody></table></div>}
    </div>
  </div>;
}
