"use client";
import {FormEvent,useState} from "react";
import Link from "next/link";
import {createClient} from "@/lib/supabase-browser";

export default function EsqueciSenha(){
  const [email,setEmail]=useState(""),[message,setMessage]=useState(""),[loading,setLoading]=useState(false);
  async function submit(e:FormEvent){
    e.preventDefault();setLoading(true);setMessage("");
    const {error}=await createClient().auth.resetPasswordForEmail(email.trim(),{
      redirectTo:`${window.location.origin}/auth/callback?next=/reset-password`
    });
    setMessage(error?error.message:"Se o e-mail estiver cadastrado, enviaremos um link para redefinir a senha.");
    setLoading(false);
  }
  return <main className="login"><form className="login-card" onSubmit={submit}>
    <h1>Recuperar acesso</h1><p>Informe o e-mail usado no Urbana Café.</p>
    {message&&<div className="notice">{message}</div>}
    <label className="field"><span>E-mail</span><input type="email" value={email} onChange={e=>setEmail(e.target.value)} required /></label>
    <button className="btn" disabled={loading}>{loading?"Enviando...":"Enviar link de recuperação"}</button>
    <p style={{marginTop:18}}><Link href="/login">Voltar para entrar</Link></p>
  </form></main>;
}
