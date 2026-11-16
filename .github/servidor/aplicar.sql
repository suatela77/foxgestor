CREATE OR REPLACE FUNCTION public.fox_reminder_candidates(p_user uuid, p_day date)
 RETURNS TABLE(client_id text, due_date date, offset_days integer, number text, message text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with client_notices as (
 with customers as (
  select
   c,public.fox_reminder_date(c->>'fim') as due,
   public.fox_reminder_number(c->>'zap') as phone
  from public.fox_state s
  cross join lateral jsonb_array_elements(
   case when jsonb_typeof(s.payload->'clientes')='array'
   then s.payload->'clientes' else '[]'::jsonb end
  ) c
  where s.user_id=p_user
  and public.fox_network_allowed(p_user)
 ), eligible as (
  select distinct on (c->>'id')
   c,due,phone,due-p_day as delta
  from customers
  where nullif(c->>'id','') is not null
  and phone is not null
  and due-p_day in (3,0,-2)
  and coalesce(c->>'status','ativo') in ('ativo','vencido')
  and coalesce(c->>'avisosWhatsapp','true')<>'false'
  and case due-p_day
   when 3 then coalesce(c->>'aviso3Dias','true')<>'false'
   when 0 then coalesce(c->>'avisoNoDia','true')<>'false'
   when -2 then coalesce(c->>'aviso2DiasDepois','true')<>'false'
   else false
  end
  order by c->>'id'
 )
 select
  c->>'id',due,delta,phone,
  '🦊 Olá, *'||
  upper(left(split_part(coalesce(nullif(trim(c->>'nome'),''),'cliente'),' ',1),60))
  ||'*! '||
  case when nullif(trim(regexp_replace(c->>'plano','\s*\(\s*R\$[^)]*\)\s*$','')),'') is not null
   then 'Seu plano *'||left(trim(regexp_replace(c->>'plano','\s*\(\s*R\$[^)]*\)\s*$','')),60)||'* '
   else 'Sua assinatura ' end
  ||case delta
   when 3 then 'vence em *3 dias* ('||to_char(due,'DD/MM')||').'
   when 0 then 'vence *hoje* ('||to_char(due,'DD/MM')||').'
   else 'venceu em *'||to_char(due,'DD/MM')||'*.'
  end
  ||case when (c->>'valor') ~ '^[0-9]+(\.[0-9]+)?$' and (c->>'valor')::numeric>0
   then E'\n💰 '||case when delta<0 then 'Valor para renovar' else 'Valor da renovação' end
    ||': *R$ '||replace(to_char(round((c->>'valor')::numeric,2),'FM9999999990.00'),'.',',')||'*'
   else '' end
  ||E'\n'||
  case delta
   when 3 then 'Renove com antecedência e continue assistindo sem interrupção! 💚'
   when 0 then 'Faça o pagamento e envie o comprovante aqui para continuar assistindo! 💚'
   else 'Renove hoje para voltar a assistir! Qualquer dúvida, estamos à disposição. 💚'
  end
 from eligible
)
select * from client_notices
union all
select
 'fox-subscription:'||a.user_id::text,
 s.due_date,s.due_date-p_day,
 public.fox_reminder_number(a.whatsapp),
 'Olá, '||
 left(coalesce(nullif(trim(a.name),''),'revenda'),100)
 ||'! 🦊'||E'\n'||
 case s.due_date-p_day
  when 3 then 'Sua assinatura do Gestor Fox vence em 3 dias, em '
  when 0 then 'Sua assinatura do Gestor Fox vence hoje, '
  else 'Sua assinatura do Gestor Fox venceu há 2 dias, em '
 end
 ||to_char(s.due_date,'DD/MM/YYYY')
 ||E'.\nMensalidade: R$ '
 ||replace(s.amount::text,'.',',')||E'.\n'||
 case
  when s.trust_until>now() then
   'Acesso liberado em confiança até '||
   to_char(
    s.trust_until at time zone 'America/Sao_Paulo',
    'DD/MM/YYYY HH24:MI'
   )||' (Brasília). '
  when now()<(
   (s.due_date+time '18:00')
   at time zone 'America/Sao_Paulo'
  ) then
   'O acesso ao painel será bloqueado às 18h do dia do vencimento (Brasília). '
  else
   'O acesso ao painel está bloqueado até a confirmação do pagamento. '
 end
 ||'Fale conosco por aqui para renovar. Se já renovou, desconsidere este aviso. Gestor Fox.'
from public.fox_subscriptions s
join public.fox_accounts a on a.user_id=s.user_id
where p_user='84560942-007c-4291-8f8a-a64466adb345'::uuid
and a.role='revenda'
and a.active
and a.archived_at is null
and public.fox_network_allowed(a.parent_id)
and s.notify
and s.due_date-p_day in (3,0,-2)
and p_day>=a.access_start
and public.fox_reminder_number(a.whatsapp) is not null;
$function$

