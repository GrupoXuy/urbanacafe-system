import {NextResponse} from "next/server";
import {createServerSupabaseClient} from "@/lib/supabase-server";
import {createAdminSupabaseClient} from "@/lib/supabase-admin";

const roles=["owner","manager","cashier","waiter","stockkeeper","analyst"] as const;
type Role=typeof roles[number];
const isRole=(value:string):value is Role=>(roles as readonly string[]).includes(value);

async function authorize(businessId:string){
  const supabase=await createServerSupabaseClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return {supabase,user:null,membership:null};
  const {data:membership}=await supabase.from("business_memberships").select("role").eq("business_id",businessId).eq("user_id",user.id).eq("active",true).maybeSingle();
  return {supabase,user,membership};
}

export async function GET(request:Request){
  try{
    const businessId=new URL(request.url).searchParams.get("businessId")||"";
    if(!businessId)return NextResponse.json({error:"Negócio obrigatório"},{status:400});
    const {supabase,user,membership}=await authorize(businessId);
    if(!user)return NextResponse.json({error:"Não autenticado"},{status:401});
    if(!membership||!["owner","manager"].includes(membership.role))return NextResponse.json({error:"Sem permissão"},{status:403});
    const {data:members,error}=await supabase.from("business_memberships").select("business_id,user_id,role,active,created_at").eq("business_id",businessId).order("created_at",{ascending:true});
    if(error)throw error;
    const admin=createAdminSupabaseClient();
    const enriched=await Promise.all((members||[]).map(async m=>{
      const [{data:profile},{data:userResult}]=await Promise.all([
        admin.from("profiles").select("full_name,phone").eq("id",m.user_id).maybeSingle(),
        admin.auth.admin.getUserById(m.user_id)
      ]);
      const authUser=userResult.user;
      return {...m,profile:profile||null,email:authUser?.email||null,confirmedAt:authUser?.email_confirmed_at||null,lastSignInAt:authUser?.last_sign_in_at||null};
    }));
    return NextResponse.json({members:enriched});
  }catch(error){return NextResponse.json({error:error instanceof Error?error.message:"Erro interno"},{status:500})}
}

export async function POST(request:Request){
  try{
    const body=await request.json(),action=String(body.action||""),businessId=String(body.businessId||"");
    const {supabase,user,membership}=await authorize(businessId);
    if(!user)return NextResponse.json({error:"Não autenticado"},{status:401});
    if(!businessId)return NextResponse.json({error:"Negócio obrigatório"},{status:400});
    if(!membership||!["owner","manager"].includes(membership.role))return NextResponse.json({error:"Sem permissão para administrar funcionários"},{status:403});
    const admin=createAdminSupabaseClient();

    if(action==="invite"){
      const email=String(body.email||"").trim().toLowerCase(),fullName=String(body.fullName||"").trim(),phone=String(body.phone||"").trim(),role=String(body.role||"cashier");
      if(!email||!email.includes("@"))return NextResponse.json({error:"E-mail inválido"},{status:400});
      if(!isRole(role))return NextResponse.json({error:"Cargo inválido"},{status:400});
      if(role==="owner"&&membership.role!=="owner")return NextResponse.json({error:"Somente o proprietário pode convidar outro proprietário"},{status:403});
      const {data:invite,error:inviteError}=await admin.auth.admin.inviteUserByEmail(email);
      if(inviteError)return NextResponse.json({error:inviteError.message},{status:400});
      if(!invite.user)return NextResponse.json({error:"O convite não retornou o usuário"},{status:400});
      const {error:profileError}=await admin.from("profiles").upsert({id:invite.user.id,full_name:fullName||null,phone:phone||null,active:true});
      if(profileError)throw profileError;
      const {error:insertError}=await admin.from("business_memberships").insert({business_id:businessId,user_id:invite.user.id,role,active:true});
      if(insertError)throw insertError;
      await admin.from("audit_logs").insert({business_id:businessId,user_id:user.id,action:"employee_invited",entity:"business_memberships",entity_id:invite.user.id,new_data:{role,email}});
      return NextResponse.json({ok:true});
    }

    if(action==="update"||action==="remove"){
      const targetUserId=String(body.userId||"");
      if(!targetUserId||targetUserId===user.id)return NextResponse.json({error:"Usuário alvo inválido ou igual ao usuário atual"},{status:400});
      const {data:target,error:targetError}=await supabase.from("business_memberships").select("user_id,role,active").eq("business_id",businessId).eq("user_id",targetUserId).maybeSingle();
      if(targetError)throw targetError;
      if(!target)return NextResponse.json({error:"Funcionário não encontrado"},{status:404});

      if(target.role==="owner"&&membership.role!=="owner")return NextResponse.json({error:"Gerentes não podem alterar acessos de proprietários"},{status:403});

      const nextRole=action==="remove"?target.role:String(body.role||target.role);
      const nextActive=action==="remove"?false:Boolean(body.active);
      if(!isRole(nextRole))return NextResponse.json({error:"Cargo inválido"},{status:400});
      if(nextRole==="owner"&&membership.role!=="owner")return NextResponse.json({error:"Somente o proprietário pode atribuir o cargo de proprietário"},{status:403});

      if(target.role==="owner"&&(nextRole!=="owner"||!nextActive)){
        const {count}=await admin.from("business_memberships").select("user_id",{count:"exact",head:true}).eq("business_id",businessId).eq("active",true).eq("role","owner");
        if((count||0)<=1)return NextResponse.json({error:"O negócio precisa manter pelo menos um proprietário ativo"},{status:400});
      }

      const {error}=await admin.from("business_memberships").update({role:nextRole,active:nextActive}).eq("business_id",businessId).eq("user_id",targetUserId);
      if(error)throw error;
      const {error:profileError}=await admin.from("profiles").update({active:nextActive}).eq("id",targetUserId);
      if(profileError)throw profileError;
      await admin.from("audit_logs").insert({business_id:businessId,user_id:user.id,action:action==="remove"?"employee_access_removed":"employee_access_updated",entity:"business_memberships",entity_id:targetUserId,old_data:{role:target.role,active:target.active},new_data:{role:nextRole,active:nextActive}});
      return NextResponse.json({ok:true});
    }

    if(action==="resend_invite"||action==="reset"){
      const targetUserId=String(body.userId||"");
      if(!targetUserId||targetUserId===user.id)return NextResponse.json({error:"Usuário alvo inválido"},{status:400});
      const {data:target}=await supabase.from("business_memberships").select("user_id,role,active").eq("business_id",businessId).eq("user_id",targetUserId).maybeSingle();
      if(!target)return NextResponse.json({error:"Funcionário não encontrado"},{status:404});
      if(target.role==="owner"&&membership.role!=="owner")return NextResponse.json({error:"Gerentes não podem operar acesso de proprietários"},{status:403});
      const {data:userResult,error:userError}=await admin.auth.admin.getUserById(targetUserId);
      if(userError||!userResult.user?.email)return NextResponse.json({error:"E-mail do usuário não disponível"},{status:400});
      if(action==="resend_invite"){
        if(userResult.user.email_confirmed_at)return NextResponse.json({error:"Este acesso já foi confirmado; use redefinir senha"},{status:400});
        const {error}=await admin.auth.admin.inviteUserByEmail(userResult.user.email);
        if(error)return NextResponse.json({error:error.message},{status:400});
        await admin.from("audit_logs").insert({business_id:businessId,user_id:user.id,action:"employee_invite_resent",entity:"business_memberships",entity_id:targetUserId});
        return NextResponse.json({ok:true});
      }
      const {data,error}=await admin.auth.admin.generateLink({type:"recovery",email:userResult.user.email,options:{redirectTo:"https://urbanacafe-system.vercel.app/auth/callback?next=/reset-password"}});
      if(error)throw error;
      const actionLink=(data as {properties?:{action_link?:string};action_link?:string}).properties?.action_link||(data as {action_link?:string}).action_link;
      if(!actionLink)throw new Error("Não foi possível gerar o link de recuperação");
      await admin.from("audit_logs").insert({business_id:businessId,user_id:user.id,action:"employee_password_reset_link_generated",entity:"business_memberships",entity_id:targetUserId});
      return NextResponse.json({ok:true,actionLink});
    }

    return NextResponse.json({error:"Ação inválida"},{status:400});
  }catch(error){return NextResponse.json({error:error instanceof Error?error.message:"Erro interno"},{status:500})}
}
