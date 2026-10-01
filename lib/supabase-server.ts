import {createServerClient} from "@supabase/ssr";
import {cookies} from "next/headers";
import {SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY} from "@/lib/supabase-config";

export async function createServerSupabaseClient(){
  const cookieStore=await cookies();
  return createServerClient(
    SUPABASE_URL,
    SUPABASE_PUBLISHABLE_KEY,
    {
      cookies:{
        getAll(){return cookieStore.getAll()},
        setAll(cookiesToSet){
          try{cookiesToSet.forEach(({name,value,options})=>cookieStore.set(name,value,options))}
          catch{}
        }
      }
    }
  );
}
