"use client";

import Link from "next/link";
import {FormEvent,useState} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase-browser";

export default function Cadastro(){
  const router=useRouter();
  const [name,setName]=useState("");
  const [business,setBusiness]=useState("Urbana Café");
  const [email,setEmail]=useState("");
  const [password,setPassword]=useState("");
  const [message,setMessage]=useState("");
  const [loading,setLoading]=useState(false);

  async function submit(e:FormEvent){
    e.preventDefault();
    setLoading(true);
    setMessage("");
    const supabase=createClient();
    const {data,error}=await supabase.auth.signUp({
      email:email.trim(),
      password,
      options:{
        data:{full_name:name.trim(),business_name:business.trim()||"Urbana Café"},
        emailRedirectTo:"https://urbanacafe-system.vercel.app/auth/callback?next=/dashboard"
      }
    });
    if(error){
      setMessage(error.message);
      setLoading(false);
      return;
    }
    if(data.session){
      const {error:setupError}=await supabase.rpc("setup_business",{
        p_name:business.trim()||"Urbana Café",
        p_full_name:name.trim()||null
      });
      if(setupError){
        setMessage(setupError.message);
        setLoading(false);
        return;
      }
      router.push("/dashboard");
      return;
    }
    setMessage("Cadastro criado. Verifique seu e-mail para confirmar o acesso e depois entre no sistema.");
    setLoading(false);
  }

  return (
    <main className="login">
      <form className="login-card" onSubmit={submit}>
        <h1>Primeiro acesso</h1>
        <p>Crie o acesso administrativo do Urbana Café.</p>

        {message&&<div className="notice">{message}</div>}

        <label className="field">
          <span>Nome completo</span>
          <input value={name} onChange={e=>setName(e.target.value)} required />
        </label>

        <label className="field">
          <span>Empresa</span>
          <input value={business} onChange={e=>setBusiness(e.target.value)} required />
        </label>

        <label className="field">
          <span>E-mail</span>
          <input type="email" value={email} onChange={e=>setEmail(e.target.value)} required />
        </label>

        <label className="field">
          <span>Senha</span>
          <input type="password" value={password} onChange={e=>setPassword(e.target.value)} minLength={8} required />
        </label>

        <button className="btn" disabled={loading}>
          {loading?"Criando acesso...":"Criar acesso"}
        </button>

        <p style={{marginTop:18}}>
          Já possui acesso? <Link href="/login">Voltar para entrar</Link>
        </p>
      </form>
    </main>
  );
}
