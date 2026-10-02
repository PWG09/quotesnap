import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

function cleanSlug(value:string){return value.toLowerCase().trim().replace(/[^a-z0-9]+/g,"-").replace(/^-+|-+$/g,"").slice(0,60);}

export async function POST(request:Request){
  const supabase=await createClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return NextResponse.json({error:"You must be signed in."},{status:401});
  let body:any; try{body=await request.json();}catch{return NextResponse.json({error:"Invalid request."},{status:400});}
  const name=typeof body.name==="string"?body.name.trim():"";
  const slug=cleanSlug(typeof body.slug==="string"?body.slug:name);
  if(!name||name.length>120||!slug)return NextResponse.json({error:"Enter a valid business name."},{status:400});
  const {data:existing}=await supabase.from("qs_organization_members").select("organization_id").eq("user_id",user.id).limit(1);
  if(existing?.length)return NextResponse.json({ok:true});
  const {error}=await supabase.from("qs_organizations").insert({owner_id:user.id,name,slug});
  if(error){
    if(error.code==="23505")return NextResponse.json({error:"That business URL is already in use. Try a more specific name."},{status:409});
    return NextResponse.json({error:"We couldn't create your workspace. Please try again."},{status:500});
  }
  return NextResponse.json({ok:true});
}
