"use client";
import {FormEvent,Suspense,useState} from "react";
import Link from "next/link";
import {useRouter,useSearchParams} from "next/navigation";
import {createClient} from "@/lib/supabase-browser";

function LoginForm(){
  const [email,setEmail]=useState(""),[password,setPassword]=useState(""),[error,setError]=useState(""),[loading,setLoading]=useState(false);
  const router=useRouter(),searchParams=useSearchParams();
  async function submit(e:FormEvent){
    e.preventDefault();setLoading(true);setError("");
    const {error}=await createClient().auth.signInWithPassword({email:email.trim(),password});
    if(error)setError(error.message);else router.push("/dashboard");setLoading(false);
  }
  const queryError=searchParams.get("error");
  const queryMessage=queryError==="auth_callback"?"Não foi possível concluir a autenticação. Solicite um novo link e tente novamente.":queryError==="missing_code"?"Link de autenticação inválido.":"";
  return <main className="login"><form className="login-card" onSubmit={submit}>
    <h1>Urbana <span style={{color:"#b68b3c"}}>Café</span></h1><p>Acesso administrativo</p>
    {(error||queryMessage)&&<div className="notice">{error||queryMessage}</div>}
    <label className="field"><span>E-mail</span><input type="email" value={email} onChange={e=>setEmail(e.target.value)} required /></label>
    <label className="field"><span>Senha</span><input type="password" value={password} onChange={e=>setPassword(e.target.value)} required /></label>
    <button className="btn" disabled={loading}>{loading?"Entrando...":"Entrar"}</button>
    <p style={{marginTop:14}}><Link href="/esqueci-senha">Esqueci minha senha</Link></p>
    <p style={{marginTop:10,fontSize:13}}>Novos colaboradores são adicionados pelo administrador em Funcionários.</p>
  </form></main>;
}
export default function Login(){
  return <Suspense fallback={<main className="login"><div className="login-card"><p>Carregando...</p></div></main>}><LoginForm/></Suspense>;
}
