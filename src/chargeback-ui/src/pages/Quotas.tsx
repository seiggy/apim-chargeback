import { useEffect, useState, useCallback } from "react"
import { fetchPlans, fetchClients, assignClient, removeClient } from "../api"
import type { PlanData, ClientAssignment } from "../types"
import { Card, CardContent, CardHeader, CardTitle } from "../components/ui/card"
import { Button } from "../components/ui/button"
import { Input } from "../components/ui/input"
import { Progress } from "../components/ui/progress"
import { Badge } from "../components/ui/badge"
import { Dialog, DialogHeader, DialogTitle, DialogClose } from "../components/ui/dialog"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../components/ui/table"
import { Pencil, Trash2, Plus, Users } from "lucide-react"

export function Clients({ onSelectClient }: { onSelectClient?: (clientAppId: string) => void }) {
  const [plans, setPlans] = useState<PlanData[]>([])
  const [clients, setClients] = useState<ClientAssignment[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [deleteConfirm, setDeleteConfirm] = useState<string | null>(null)

  // Client dialog state
  const [clientDialogOpen, setClientDialogOpen] = useState(false)
  const [editingClientId, setEditingClientId] = useState<string | null>(null)
  const [clientAppIdInput, setClientAppIdInput] = useState("")
  const [clientPlanId, setClientPlanId] = useState("")
  const [clientDisplayName, setClientDisplayName] = useState("")

  const loadData = useCallback(async () => {
    try {
      const [plansRes, clientsRes] = await Promise.all([fetchPlans(), fetchClients()])
      setPlans(plansRes.plans ?? [])
      setClients(clientsRes.clients ?? [])
      setError(null)
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load data")
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => { loadData() }, [loadData])

  const openAssignClient = () => {
    setEditingClientId(null)
    setClientAppIdInput("")
    setClientPlanId(plans.length > 0 ? plans[0].id : "")
    setClientDisplayName("")
    setClientDialogOpen(true)
  }

  const openEditClient = (c: ClientAssignment) => {
    setEditingClientId(c.clientAppId)
    setClientAppIdInput(c.clientAppId)
    setClientPlanId(c.planId)
    setClientDisplayName(c.displayName)
    setClientDialogOpen(true)
  }

  const handleSaveClient = async () => {
    setSaving(true)
    try {
      await assignClient(editingClientId ?? clientAppIdInput, {
        planId: clientPlanId,
        displayName: clientDisplayName || undefined,
      })
      setClientDialogOpen(false)
      await loadData()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save client assignment")
    } finally {
      setSaving(false)
    }
  }

  const handleRemoveClient = async (clientAppId: string) => {
    try {
      await removeClient(clientAppId)
      setDeleteConfirm(null)
      await loadData()
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to remove client")
    }
  }

  const getPlanName = (planId: string) => plans.find((p) => p.id === planId)?.name ?? planId
  const getPlan = (planId: string) => plans.find((p) => p.id === planId)

  if (error && clients.length === 0) {
    return (
      <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-4 text-destructive">
        Error: {error}
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Users className="h-6 w-6 text-[#0078D4]" />
        <h2 className="text-xl font-bold">Client Management</h2>
      </div>

      {error && (
        <div className="rounded-lg border border-destructive/50 bg-destructive/10 p-3 text-destructive text-sm">
          {error}
          <Button variant="ghost" size="sm" className="ml-2" onClick={() => setError(null)}>Dismiss</Button>
        </div>
      )}

      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle className="text-base">Client Assignments</CardTitle>
          <Button size="sm" className="gap-1" onClick={openAssignClient}>
            <Plus className="h-4 w-4" /> Assign Client
          </Button>
        </CardHeader>
        <CardContent>
          {loading ? (
            <div className="text-center text-muted-foreground py-8">Loading clients…</div>
          ) : clients.length === 0 ? (
            <div className="text-center text-muted-foreground py-8">No client assignments yet.</div>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Client App ID</TableHead>
                  <TableHead>Display Name</TableHead>
                  <TableHead>Plan</TableHead>
                  <TableHead>Usage</TableHead>
                  <TableHead>Deployment Usage</TableHead>
                  <TableHead>Overbilled Tokens</TableHead>
                  <TableHead className="w-[100px]">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {clients.map((c) => {
                  const plan = getPlan(c.planId)
                  const quota = plan?.monthlyTokenQuota ?? 1
                  const pct = quota > 0 ? (c.currentPeriodUsage / quota) * 100 : 0
                  return (
                    <TableRow key={c.clientAppId}>
                      <TableCell>
                        <button
                          className="font-mono text-xs text-[#0078D4] hover:underline cursor-pointer"
                          onClick={() => onSelectClient?.(c.clientAppId)}
                        >
                          {c.clientAppId}
                        </button>
                      </TableCell>
                      <TableCell>{c.displayName || "—"}</TableCell>
                      <TableCell>
                        <Badge variant="blue">{getPlanName(c.planId)}</Badge>
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-3">
                          <Progress value={c.currentPeriodUsage} max={quota} className="w-24" />
                          <span className="text-xs text-muted-foreground font-mono">{pct.toFixed(1)}%</span>
                        </div>
                      </TableCell>
                      <TableCell>
                        {c.deploymentUsage && Object.keys(c.deploymentUsage).length > 0 ? (
                          <div className="space-y-1">
                            {Object.entries(c.deploymentUsage).map(([depId, usage]) => (
                              <div key={depId} className="flex items-center gap-1 text-xs">
                                <span className="font-mono text-muted-foreground">{depId}:</span>
                                <span className="font-mono">{usage.toLocaleString()}</span>
                              </div>
                            ))}
                          </div>
                        ) : (
                          <span className="text-muted-foreground text-xs">—</span>
                        )}
                      </TableCell>
                      <TableCell>
                        {c.overbilledTokens > 0 ? (
                          <Badge variant="red">{c.overbilledTokens.toLocaleString()}</Badge>
                        ) : (
                          <span className="text-muted-foreground font-mono">0</span>
                        )}
                      </TableCell>
                      <TableCell>
                        <div className="flex gap-1">
                          <Button variant="ghost" size="icon" onClick={() => openEditClient(c)}>
                            <Pencil className="h-4 w-4" />
                          </Button>
                          <Button variant="ghost" size="icon" onClick={() => setDeleteConfirm(c.clientAppId)}>
                            <Trash2 className="h-4 w-4 text-[#D13438]" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {/* Client Assign/Edit Dialog */}
      <Dialog open={clientDialogOpen} onOpenChange={(open) => !open && setClientDialogOpen(false)}>
        <DialogClose onClose={() => setClientDialogOpen(false)} />
        <DialogHeader>
          <DialogTitle>{editingClientId ? "Edit Client Assignment" : "Assign Client"}</DialogTitle>
        </DialogHeader>
        <div className="mt-4 space-y-4">
          <div className="space-y-2">
            <label className="text-sm font-medium">Client App ID</label>
            <Input
              value={clientAppIdInput}
              onChange={(e) => setClientAppIdInput(e.target.value)}
              placeholder="Client application ID"
              disabled={!!editingClientId}
            />
          </div>
          <div className="space-y-2">
            <label className="text-sm font-medium">Plan</label>
            <select
              className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              value={clientPlanId}
              onChange={(e) => setClientPlanId(e.target.value)}
            >
              {plans.map((p) => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>
          </div>
          <div className="space-y-2">
            <label className="text-sm font-medium">Display Name</label>
            <Input value={clientDisplayName} onChange={(e) => setClientDisplayName(e.target.value)} placeholder="Optional display name" />
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setClientDialogOpen(false)}>Cancel</Button>
            <Button onClick={handleSaveClient} disabled={saving || (!editingClientId && !clientAppIdInput) || !clientPlanId}>
              {saving ? "Saving…" : editingClientId ? "Update" : "Assign"}
            </Button>
          </div>
        </div>
      </Dialog>

      {/* Delete Confirmation Dialog */}
      <Dialog open={!!deleteConfirm} onOpenChange={(open) => !open && setDeleteConfirm(null)}>
        <DialogClose onClose={() => setDeleteConfirm(null)} />
        <DialogHeader>
          <DialogTitle>Confirm Delete</DialogTitle>
        </DialogHeader>
        <div className="mt-4 space-y-4">
          <p className="text-sm text-muted-foreground">
            Are you sure you want to delete this client assignment? This action cannot be undone.
          </p>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setDeleteConfirm(null)}>Cancel</Button>
            <Button
              variant="destructive"
              onClick={() => {
                if (deleteConfirm) handleRemoveClient(deleteConfirm)
              }}
            >
              Delete
            </Button>
          </div>
        </div>
      </Dialog>
    </div>
  )
}
