"use client";
import {useState} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase-browser";

export default function Setup(){
  const [name,setName]=useState("Urbana Café"),[legalName,setLegalName]=useState("Urbana Café y Resto"),[fullName,setFullName]=useState(""),[message,setMessage]=useState(""),[saving,setSaving]=useState(false);
  const router=useRouter();

  async function submit(e:React.FormEvent){
    e.preventDefault();setSaving(true);setMessage("");
    const {error}=await createClient().rpc("setup_business",{p_name:name,p_legal_name:legalName,p_full_name:fullName});
    if(error)setMessage(error.message);else router.push("/dashboard");
    setSaving(false);
  }

  return <main className="login"><form className="login-card" onSubmit={submit}>
    <h1>Configurar <span style={{color:"#b68b3c"}}>Urbana Café</span></h1>
    <p>Primeira configuração do negócio e criação do usuário proprietário.</p>
    <label className="field"><span>Nome comercial</span><input value={name} onChange={e=>setName(e.target.value)} required/></label>
    <label className="field"><span>Razão social</span><input value={legalName} onChange={e=>setLegalName(e.target.value)}/></label>
    <label className="field"><span>Seu nome</span><input value={fullName} onChange={e=>setFullName(e.target.value)} placeholder="Nome do proprietário" required/></label>
    <button className="btn" disabled={saving}>{saving?"Configurando...":"Criar negócio e continuar"}</button>
    {message&&<div className="notice">{message}</div>}
  </form></main>
}
