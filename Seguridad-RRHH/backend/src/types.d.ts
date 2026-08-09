declare namespace Express { interface Request { user?: { id:string; role:string; permisos:Record<string,boolean|string>; guardia_id?:string; must_change_password?:boolean } } }
