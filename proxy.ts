import {createServerClient} from "@supabase/ssr";
import {NextResponse,type NextRequest} from "next/server";
import {SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY} from "@/lib/supabase-config";

export async function proxy(request:NextRequest){
  let response=NextResponse.next({request});
  const supabase=createServerClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{cookies:{
    getAll(){return request.cookies.getAll()},
    setAll(cookies){cookies.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request});cookies.forEach(({name,value,options})=>response.cookies.set(name,value,options))}
  }});
  const {data:{user}}=await supabase.auth.getUser();
  if((request.nextUrl.pathname.startsWith("/dashboard")||request.nextUrl.pathname==="/setup"||request.nextUrl.pathname==="/reset-password")&&!user)return NextResponse.redirect(new URL("/login",request.url));
  if((request.nextUrl.pathname==="/login"||request.nextUrl.pathname==="/setup"||request.nextUrl.pathname==="/cadastro")&&user)return NextResponse.redirect(new URL("/dashboard",request.url));
  return response;
}
export const config={matcher:["/dashboard/:path*","/login","/setup","/cadastro","/reset-password"]};
