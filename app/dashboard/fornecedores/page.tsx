"use client";
import {FormEvent,useEffect,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

type Supplier={id:string;name:string;phone:string|null;email:string|null;notes:string|null;active:boolean;created_at:string};

export default function Fornecedores(){
  const [business,setBusiness]=useState("");
  const [items,setItems]=useState<Supplier[]>([]);
  const [editing,setEditing]=useState<string|null>(null);
  const [name,setName]=useState("");
  const [phone,setPhone]=useState("");
  const [email,setEmail]=useState("");
  const [notes,setNotes]=useState("");
  const [search,setSearch]=useState("");
  const [message,setMessage]=useState("");
  const [saving,setSaving]=useState(false);

  async function load(){
    const c=createClient();
    const {data:{user}}=await c.auth.getUser();
    if(!user)return;
    const {data:m}=await c.from("business_memberships").select("business_id").eq("user_id",user.id).eq("active",true).limit(1).maybeSingle();
    if(!m)return;
    setBusiness(m.business_id);
    const {data}=await c.from("suppliers").select("id,name,phone,email,notes,active,created_at").eq("business_id",m.business_id).order("name");
    setItems((data||[]) as Supplier[]);
  }
  useEffect(()=>{load()},[]);

  function reset(){setEditing(null);setName("");setPhone("");setEmail("");setNotes("")}
  function edit(s:Supplier){setEditing(s.id);setName(s.name);setPhone(s.phone||"");setEmail(s.email||"");setNotes(s.notes||"");window.scrollTo({top:0,behavior:"smooth"})}

  async function save(e:FormEvent){
    e.preventDefault();setSaving(true);setMessage("");
    const c=createClient();
    const payload={business_id:business,name:name.trim(),phone:phone.trim()||null,email:email.trim()||null,notes:notes.trim()||null,active:true};
    const result=editing
      ? await c.from("suppliers").update(payload).eq("id",editing).eq("business_id",business)
      : await c.from("suppliers").insert(payload);
    if(result.error)setMessage(result.error.message);
    else{setMessage(editing?"Fornecedor atualizado.":"Fornecedor cadastrado.");reset();await load()}
    setSaving(false);
  }

  async function toggle(s:Supplier){
    setMessage("");
    const {error}=await createClient().from("suppliers").update({active:!s.active}).eq("id",s.id).eq("business_id",business);
    if(error)setMessage(error.message);else await load();
  }

  const filtered=items.filter(s=>[s.name,s.phone||"",s.email||""].join(" ").toLowerCase().includes(search.toLowerCase()));

  return <div className="main">
    <div className="topbar">
      <div><h1 className="title">Fornecedores</h1><p className="subtitle">Cadastro de parceiros e contatos de compras</p></div>
      <Link href="/dashboard/compras" className="btn" style={{width:"auto",textDecoration:"none"}}>Voltar para compras</Link>
    </div>

    <form className="card section" onSubmit={save}>
      <h2>{editing?"Editar fornecedor":"Novo fornecedor"}</h2>
      <div className="grid" style={{gridTemplateColumns:"repeat(3,minmax(0,1fr))"}}>
        <label className="field"><span>Nome</span><input value={name} onChange={e=>setName(e.target.value)} required/></label>
        <label className="field"><span>Telefone</span><input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="+598 ..."/></label>
        <label className="field"><span>E-mail</span><input type="email" value={email} onChange={e=>setEmail(e.target.value)} placeholder="fornecedor@email.com"/></label>
      </div>
      <label className="field"><span>Observações</span><input value={notes} onChange={e=>setNotes(e.target.value)} placeholder="Produtos, condições, contato etc."/></label>
      <div style={{display:"flex",gap:10}}>
        <button className="btn" style={{width:"auto"}} disabled={!business||saving}>{saving?"Salvando...":editing?"Salvar alterações":"Cadastrar fornecedor"}</button>
        {editing&&<button type="button" className="btn" style={{width:"auto",background:"#666"}} onClick={reset}>Cancelar</button>}
      </div>
      {message&&<div className="notice">{message}</div>}
    </form>

    <div className="section">
      <input placeholder="Buscar fornecedor..." value={search} onChange={e=>setSearch(e.target.value)} style={{width:"100%",padding:12,border:"1px solid #ddd",borderRadius:9,marginBottom:12}}/>
      <table className="table">
        <thead><tr><th>Fornecedor</th><th>Telefone</th><th>E-mail</th><th>Status</th><th></th></tr></thead>
        <tbody>{filtered.map(s=><tr key={s.id}>
          <td><b>{s.name}</b>{s.notes&&<div className="subtitle">{s.notes}</div>}</td>
          <td>{s.phone||"—"}</td>
          <td>{s.email||"—"}</td>
          <td>{s.active?"Ativo":"Inativo"}</td>
          <td><div style={{display:"flex",gap:8}}><button onClick={()=>edit(s)}>Editar</button><button onClick={()=>toggle(s)}>{s.active?"Desativar":"Ativar"}</button></div></td>
        </tr>)}</tbody>
      </table>
    </div>
  </div>;
}
