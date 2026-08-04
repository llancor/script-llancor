declare namespace Express { interface Request { user?: { id:string; role:string; permisos:Record<string,boolean> } } }

