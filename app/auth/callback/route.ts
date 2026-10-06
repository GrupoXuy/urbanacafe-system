import {NextResponse} from "next/server";
import {createServerClient} from "@supabase/ssr";
import {cookies} from "next/headers";
import {SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY} from "@/lib/supabase-config";

function safeNextPath(value:string|null){
  if(!value||!value.startsWith("/")||value.startsWith("//"))return "/dashboard";
  return value;
}

export async function GET(request:Request){
  const url=new URL(request.url),code=url.searchParams.get("code"),next=safeNextPath(url.searchParams.get("next"));
  if(!code)return NextResponse.redirect(new URL("/login?error=missing_code",url.origin));
  const cookieStore=await cookies();
  const supabase=createServerClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{cookies:{
    getAll(){return cookieStore.getAll()},
    setAll(cookiesToSet){cookiesToSet.forEach(({name,value,options})=>cookieStore.set(name,value,options))}
  }});
  const {error}=await supabase.auth.exchangeCodeForSession(code);
  if(error)return NextResponse.redirect(new URL("/login?error=auth_callback",url.origin));
  return NextResponse.redirect(new URL(next,url.origin));
}
