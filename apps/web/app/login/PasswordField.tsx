'use client';

import { useState } from 'react';
import { Eye, EyeOff } from 'lucide-react';

/** Mot de passe avec le bouton œil (maquette web/w1-connexion). */
export function PasswordField() {
  const [shown, setShown] = useState(false);
  return (
    <div className="relative">
      <input
        id="password"
        name="password"
        type={shown ? 'text' : 'password'}
        autoComplete="current-password"
        required
        className="h-12 w-full rounded-md border border-sand-deep bg-white px-4 pr-12 text-[15px] text-ink focus:border-forest focus:outline-none"
      />
      <button
        type="button"
        onClick={() => setShown(!shown)}
        aria-label={shown ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
        className="absolute right-2 top-1/2 flex h-9 w-9 -translate-y-1/2 items-center justify-center rounded-md text-ink-muted hover:bg-sand"
      >
        {shown ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
      </button>
    </div>
  );
}
