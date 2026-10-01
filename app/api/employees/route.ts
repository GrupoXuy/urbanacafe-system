import {NextResponse} from "next/server";
import {createServerSupabaseClient} from "@/lib/supabase-server";
import {createAdminSupabaseClient} from "@/lib/supabase-admin";

const roles=["owner","manager","cashier","waiter","stockkeeper","analyst"] as const;
type Role=typeof roles[number];
const isRole=(value:string):value is Role=>(roles as readonly string[]).includes(value);

export async function POST(request:Request){
  try{
    const body=await request.json();
    const action=String(body.action||"");
    const businessId=String(body.businessId||"");
    const supabase=await createServerSupabaseClient();
    const {data:{user}}=await supabase.auth.getUser();

    if(!user)return NextResponse.json({error:"Não autenticado"},{status:401});
    if(!businessId)return NextResponse.json({error:"Negócio obrigatório"},{status:400});

    const {data:membership,error:membershipError}=await supabase
      .from("business_memberships").select("role")
      .eq("business_id",businessId).eq("user_id",user.id).eq("active",true).maybeSingle();

    if(membershipError||!membership||!["owner","manager"].includes(membership.role))
      return NextResponse.json({error:"Sem permissão para administrar funcionários"},{status:403});

    const admin=createAdminSupabaseClient();

    if(action==="invite"){
      const email=String(body.email||"").trim().toLowerCase();
      const fullName=String(body.fullName||"").trim();
      const phone=String(body.phone||"").trim();
      const role=String(body.role||"cashier");

      if(!email||!email.includes("@"))return NextResponse.json({error:"E-mail inválido"},{status:400});
      if(!isRole(role))return NextResponse.json({error:"Cargo inválido"},{status:400});
      if(role==="owner"&&membership.role!=="owner")
        return NextResponse.json({error:"Somente o proprietário pode convidar outro proprietário"},{status:403});

      const {data:invite,error:inviteError}=await admin.auth.admin.inviteUserByEmail(email);
      if(inviteError)return NextResponse.json({error:inviteError.message},{status:400});
      if(!invite.user)return NextResponse.json({error:"O convite não retornou o usuário"},{status:400});

      const {error:profileError}=await admin.from("profiles")
        .upsert({id:invite.user.id,full_name:fullName||null,phone:phone||null,active:true});
      if(profileError)return NextResponse.json({error:profileError.message},{status:400});

      const {error:insertError}=await admin.from("business_memberships").insert({
        business_id:businessId,user_id:invite.user.id,role,active:true
      });
      if(insertError)return NextResponse.json({error:insertError.message},{status:400});

      return NextResponse.json({ok:true});
    }

    if(action==="update"){
      const targetUserId=String(body.userId||"");
      const role=String(body.role||"");
      const active=Boolean(body.active);

      if(!targetUserId||!isRole(role))return NextResponse.json({error:"Dados inválidos"},{status:400});
      if(role==="owner"&&membership.role!=="owner")
        return NextResponse.json({error:"Somente o proprietário pode atribuir o cargo de proprietário"},{status:403});
      if(targetUserId===user.id)
        return NextResponse.json({error:"Não altere seu próprio acesso por esta tela"},{status:400});

      const {data:target}=await supabase.from("business_memberships")
        .select("user_id,role").eq("business_id",businessId).eq("user_id",targetUserId).maybeSingle();
      if(!target)return NextResponse.json({error:"Funcionário não encontrado"},{status:404});

      const {error}=await admin.from("business_memberships")
        .update({role,active}).eq("business_id",businessId).eq("user_id",targetUserId);
      if(error)return NextResponse.json({error:error.message},{status:400});

      return NextResponse.json({ok:true});
    }

    return NextResponse.json({error:"Ação inválida"},{status:400});
  }catch(error){
    return NextResponse.json({error:error instanceof Error?error.message:"Erro interno"},{status:500});
  }
}
