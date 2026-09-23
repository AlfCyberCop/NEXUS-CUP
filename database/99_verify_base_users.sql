SELECT u.id,u.nome,u.email,u.ativo,u.mudar_password,
       coalesce(array_agg(ur.role ORDER BY ur.role) FILTER (WHERE ur.role IS NOT NULL),'{}') AS roles,
       EXISTS(SELECT 1 FROM app.super_autorizado sa WHERE sa.utilizador_id=u.id) AS super_autorizado
FROM app.utilizador u
LEFT JOIN app.utilizador_role ur ON ur.utilizador_id=u.id
WHERE lower(u.email) IN (
  lower('Alfcybercop@nexuscup.pt'),
  lower('Paulo.ramalho@nexuscup.pt'),
  lower('jose.silva@nexuscup.pt'),
  lower('adalberto.costa@nexuscup.pt')
)
GROUP BY u.id,u.nome,u.email,u.ativo,u.mudar_password
ORDER BY u.id;
