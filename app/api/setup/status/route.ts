import {NextResponse} from "next/server";
import {createAdminSupabaseClient} from "@/lib/supabase-admin";
export async function GET(){
  try{
    const admin=createAdminSupabaseClient();
    const {count,error}=await admin.from("business_memberships").select("user_id",{count:"exact",head:true}).eq("active",true);
    if(error)throw error;
    return NextResponse.json({available:(count||0)===0});
  }catch{return NextResponse.json({available:false,error:"Não foi possível verificar a configuração inicial"},{status:503})}
}
