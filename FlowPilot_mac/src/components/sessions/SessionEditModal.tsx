import { useState } from "react";
import { RotateCcw, Save } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { NativeSelect } from "@/components/ui/native-select";
import { Textarea } from "@/components/ui/textarea";
import { CATEGORY_LABELS } from "../../lib/labels";
import { formatDuration } from "../../lib/time";
import type { ProductivityCategory, ReportActivitySession, SessionOverrideDraft } from "../../types/activity";

interface SessionEditModalProps {
  onClose: () => void;
  onReset: (sessionId: string) => void;
  onSave: (draft: SessionOverrideDraft) => void;
  session: ReportActivitySession;
}

const EDITABLE_CATEGORIES: ProductivityCategory[] = ["productive", "unproductive", "neutral", "ignored", "uncategorized"];

export function SessionEditModal({ onClose, onReset, onSave, session }: SessionEditModalProps) {
  const [category, setCategory] = useState<ProductivityCategory>(session.category);
  const [displayName, setDisplayName] = useState(session.displayName);
  const [note, setNote] = useState(session.note ?? "");

  function handleSave() {
    onSave({
      categoryOverride: category,
      displayNameOverride: displayName.trim() || null,
      note: note.trim() || null,
      sessionId: session.id,
    });
  }

  return (
    <Dialog open onOpenChange={(open) => {
      if (!open) {
        onClose();
      }
    }}>
      <DialogContent className="sm:max-w-[560px]">
        <DialogHeader>
          <DialogTitle id="session-edit-title">세션 수정</DialogTitle>
          <DialogDescription>
            {session.displayName} · {formatDuration(session.durationSeconds)}
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-2">
          <div className="grid gap-2">
            <Label htmlFor="session-category">분류</Label>
            <NativeSelect id="session-category" value={category} onChange={(event) => setCategory(event.target.value as ProductivityCategory)}>
              {EDITABLE_CATEGORIES.map((option) => (
                <option key={option} value={option}>
                  {CATEGORY_LABELS[option]}
                </option>
              ))}
            </NativeSelect>
          </div>

          <div className="grid gap-2">
            <Label htmlFor="session-display-name">표시 이름</Label>
            <Input id="session-display-name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} />
          </div>

          <div className="grid gap-2">
            <Label htmlFor="session-note">메모</Label>
            <Textarea id="session-note" value={note} onChange={(event) => setNote(event.target.value)} rows={4} />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" type="button" onClick={() => onReset(session.id)}>
            <RotateCcw className="size-4" />
            초기화
          </Button>
          <Button type="button" onClick={handleSave}>
            <Save className="size-4" />
            저장
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
