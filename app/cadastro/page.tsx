"use client";
import Link from "next/link";
import {FormEvent,useEffect,useState} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase-browser";

export default function Cadastro(){
  const router=useRouter(),[available,setAvailable]=useState<boolean|null>(null),[name,setName]=useState(""),[business,setBusiness]=useState("Urbana Café"),[email,setEmail]=useState(""),[password,setPassword]=useState(""),[message,setMessage]=useState(""),[loading,setLoading]=useState(false);
  useEffect(()=>{let cancelled=false;fetch("/api/setup/status").then(r=>r.json()).then(d=>{if(!cancelled)setAvailable(Boolean(d.available))}).catch(()=>{if(!cancelled)setAvailable(false)});return()=>{cancelled=true}},[]);
  async function submit(e:FormEvent){
    e.preventDefault();setLoading(true);setMessage("");
    const supabase=createClient();
    const {data,error}=await supabase.auth.signUp({email:email.trim(),password,options:{data:{full_name:name.trim(),business_name:business.trim()||"Urbana Café"},emailRedirectTo:`${window.location.origin}/auth/callback?next=/dashboard`}});
    if(error){setMessage(error.message);setLoading(false);return}
    if(data.session){
      const {error:setupError}=await supabase.rpc("setup_business",{p_name:business.trim()||"Urbana Café",p_full_name:name.trim()||null});
      if(setupError){setMessage(setupError.message);setLoading(false);return}
      router.push("/dashboard");return;
    }
    setMessage("Cadastro criado. Verifique seu e-mail para confirmar o acesso e depois entre no sistema.");setLoading(false);
  }
  if(available===null)return <main className="login"><div className="login-card"><p>Verificando configuração inicial...</p></div></main>;
  if(!available)return <main className="login"><div className="login-card"><h1>Configuração concluída</h1><p>O acesso inicial do Urbana Café já foi criado.</p><div className="notice">Novos colaboradores devem ser adicionados pelo administrador em <strong>Funcionários</strong>.</div><Link href="/login" className="btn" style={{display:"block",textAlign:"center",textDecoration:"none",marginTop:16}}>Voltar para entrar</Link></div></main>;
  return <main className="login"><form className="login-card" onSubmit={submit}>
    <h1>Primeiro acesso</h1><p>Crie o acesso administrativo do Urbana Café.</p>{message&&<div className="notice">{message}</div>}
    <label className="field"><span>Nome completo</span><input value={name} onChange={e=>setName(e.target.value)} required /></label>
    <label className="field"><span>Empresa</span><input value={business} onChange={e=>setBusiness(e.target.value)} required /></label>
    <label className="field"><span>E-mail</span><input type="email" value={email} onChange={e=>setEmail(e.target.value)} required /></label>
    <label className="field"><span>Senha</span><input type="password" value={password} onChange={e=>setPassword(e.target.value)} minLength={8} required /></label>
    <button className="btn" disabled={loading}>{loading?"Criando acesso...":"Criar acesso"}</button>
    <p style={{marginTop:18}}>Já possui acesso? <Link href="/login">Voltar para entrar</Link></p>
  </form></main>;
}
