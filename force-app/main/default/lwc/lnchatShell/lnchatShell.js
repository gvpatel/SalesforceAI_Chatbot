import { LightningElement, api, wire, track } from "lwc";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import sendMessage from "@salesforce/apex/LNChatController.sendMessage";
import getConversationHistory from "@salesforce/apex/LNChatController.getConversationHistory";
import clearConversationHistory from "@salesforce/apex/LNChatController.clearConversationHistory";
import executeRecordAction from "@salesforce/apex/LNChatController.executeRecordAction";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

const OBJECT_LABELS = {
  Account: "Account",
  Opportunity: "Opportunity",
  Case: "Case",
  Lead: "Lead",
  Contact: "Contact"
};

export default class LnchatShell extends NavigationMixin(LightningElement) {
  @api label = "AI Assistant";
  @api displayMode = "utility"; // 'utility' | 'sidebar'
  @api showIntentBadge = false;

  @track recordId = "";
  @track objectApiName = "";
  @track isLoading = false;
  @track isMinimized = false;
  @track conversationHistory = [];

  _pendingBypassAction = null;

  @wire(CurrentPageReference)
  handlePageRef(pageRef) {
    if (!pageRef) return;

    const attrs = pageRef.attributes || {};
    const newRecordId = attrs.recordId || "";
    const newObjectApiName = attrs.objectApiName || "";

    if (newRecordId !== this.recordId) {
      this.recordId = newRecordId;
      this.objectApiName = newObjectApiName;
      this.conversationHistory = [];

      if (this.recordId) {
        this.loadHistory();
      } else {
        const history = this.template.querySelector("c-lnchat-history");
        if (history) history.clearMessages();
      }
    }
  }

  get hasRecord() {
    return !!this.recordId;
  }

  get contextLabel() {
    const label = OBJECT_LABELS[this.objectApiName] || this.objectApiName;
    return label ? label + " record" : "Current record";
  }

  get isSidebar() {
    return this.displayMode === "sidebar";
  }

  get isDrawer() {
    return this.displayMode === "drawer";
  }

  get panelClass() {
    let cls = "chatbot-panel";
    if (this.isDrawer) cls += " panel-drawer";
    else if (this.isSidebar) cls += " panel-sidebar";
    else if (this.isMinimized) cls += " panel-minimized";
    return cls;
  }

  async loadHistory() {
    try {
      const history = await getConversationHistory({ recordId: this.recordId });
      const historyEl = this.template.querySelector("c-lnchat-history");
      if (!historyEl) return;

      historyEl.clearMessages();
      this.conversationHistory = [];

      for (const msg of history) {
        historyEl.addMessage(msg.role, msg.content, msg.responseType);
        this.conversationHistory.push({ role: msg.role, content: msg.content });
      }
    } catch {
      // Silently fail on history load — non-critical
    }
  }

  async handleMessageSend(event) {
    const { message: userMessage, attachment } = event.detail;
    if ((!userMessage && !attachment) || this.isLoading) return;

    const historyEl = this.template.querySelector("c-lnchat-history");
    if (historyEl) {
      historyEl.addMessage(
        "user",
        userMessage || "",
        null,
        attachment ? attachment.name : null
      );
    }

    const historyContent =
      userMessage || (attachment ? "[File: " + attachment.name + "]" : "");
    this.conversationHistory.push({ role: "user", content: historyContent });
    this.isLoading = true;

    try {
      const historyJson = JSON.stringify(
        this.conversationHistory.slice(-10).map((m) => ({
          role: m.role,
          content: m.content
        }))
      );

      const result = await sendMessage({
        userMessage: userMessage || "",
        recordId: this.recordId || null,
        objectApiName: this.objectApiName || null,
        conversationHistoryJson: historyJson,
        attachmentJson: attachment ? JSON.stringify(attachment) : null
      });

      const assistantContent =
        result.rawJson ||
        JSON.stringify({
          responseType: result.responseType,
          title: result.title,
          summary: result.summary,
          data: result.data,
          actions: result.actions
        });

      if (historyEl) {
        historyEl.addMessage(
          "assistant",
          assistantContent,
          result.responseType
        );
      }

      this.conversationHistory.push({
        role: "assistant",
        content: assistantContent
      });
    } catch (error) {
      // Remove the user message we just added so failed attempts don't inflate history
      this.conversationHistory.pop();

      const errorMsg = error.body
        ? error.body.message
        : error.message || "Unknown error";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "AI Assistant Error",
          message: errorMsg,
          variant: "error",
          mode: "dismissable"
        })
      );

      if (historyEl) {
        const errorJson = JSON.stringify({
          responseType: "alert",
          title: "Error",
          summary: errorMsg,
          data: {
            severity: "critical",
            alertTitle: "Request Failed",
            message: errorMsg,
            details: []
          },
          actions: []
        });
        historyEl.addMessage("assistant", errorJson, "alert");
      }
    } finally {
      this.isLoading = false;
    }
  }

  async handleClearHistory() {
    if (this.isLoading) return;

    if (this.recordId) {
      try {
        await clearConversationHistory({ recordId: this.recordId });
      } catch {
        // Non-critical — clear UI anyway
      }
    }

    const historyEl = this.template.querySelector("c-lnchat-history");
    if (historyEl) historyEl.clearMessages();
    this.conversationHistory = [];
  }

  async handleRecordActionConfirm(event) {
    const { operation, objectApiName, recordId, fields, bypassDuplicate } =
      event.detail;
    const historyEl = this.template.querySelector("c-lnchat-history");
    this.isLoading = true;

    try {
      const result = await executeRecordAction({
        objectApiName,
        operation,
        recordId: recordId || null,
        fieldsJson: JSON.stringify(fields || {}),
        currentPageRecordId: this.recordId || null,
        bypassDuplicate: bypassDuplicate === true
      });

      let responseJson;

      if (result.isDuplicate) {
        const dups = result.duplicates || [];
        const details = dups.map((d) => {
          const parts = [];
          if (d.id) parts.push("ID: " + d.id);
          if (d.name) parts.push(d.name);
          if (d.email) parts.push("Email: " + d.email);
          if (d.phone) parts.push("Phone: " + d.phone);
          if (d.account) parts.push("Account: " + d.account);
          if (d.company) parts.push("Company: " + d.company);
          if (d.stage) parts.push("Stage: " + d.stage);
          if (d.status) parts.push("Status: " + d.status);
          if (d.number) parts.push("Case #: " + d.number);
          if (d.city) parts.push(d.city + (d.state ? ", " + d.state : ""));
          return parts.join("  |  ");
        });

        if (result.isAmbiguous) {
          responseJson = JSON.stringify({
            responseType: "alert",
            title: "Ambiguous Record — Action Blocked",
            summary:
              "Found " +
              (dups.length + 1) +
              " " +
              objectApiName +
              " records with the same name. Please tell me which one to update by specifying the Record ID.",
            data: {
              severity: "warning",
              alertTitle: "Multiple " + objectApiName + " Records Found",
              message:
                "These records share the same name. Specify the Record ID of the one you want to update:",
              details
            },
            actions: []
          });
        } else {
          // Store action details so user can proceed past the warning
          this._pendingBypassAction = {
            operation,
            objectApiName,
            recordId,
            fields
          };
          responseJson = JSON.stringify({
            responseType: "alert",
            title: "Duplicate Found — Confirm to Proceed",
            summary:
              dups.length +
              ' existing record(s) already have similar values. Click "Proceed Anyway" to create the record regardless, or "Cancel" to abort.',
            data: {
              severity: "warning",
              alertTitle: "Duplicate " + objectApiName + " Record(s) Found",
              message:
                "The following existing record(s) may conflict with your request:",
              details,
              allowBypass: true
            },
            actions: []
          });
        }
      } else {
        const noun =
          operation === "update"
            ? objectApiName + " updated"
            : objectApiName + " created";
        responseJson = JSON.stringify({
          responseType: "alert",
          title: "Success",
          summary: noun + " successfully.",
          data: {
            severity: "success",
            alertTitle: noun.charAt(0).toUpperCase() + noun.slice(1),
            message:
              noun.charAt(0).toUpperCase() + noun.slice(1) + " successfully.",
            details: result.recordId ? ["Record ID: " + result.recordId] : []
          },
          actions: []
        });
      }

      if (historyEl) historyEl.addMessage("assistant", responseJson, "alert");
      this.conversationHistory.push({
        role: "assistant",
        content: responseJson
      });
    } catch (error) {
      const errorMsg = error.body
        ? error.body.message
        : error.message || "Record action failed";
      const errorJson = JSON.stringify({
        responseType: "alert",
        title: "Error",
        summary: errorMsg,
        data: {
          severity: "critical",
          alertTitle: "Action Failed",
          message: errorMsg,
          details: []
        },
        actions: []
      });
      if (historyEl) historyEl.addMessage("assistant", errorJson, "alert");
    } finally {
      this.isLoading = false;
    }
  }

  handleAttachError(event) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "File Attachment",
        message: event.detail.message,
        variant: "error",
        mode: "dismissable"
      })
    );
  }

  handleRecordActionCancel() {
    const cancelJson = JSON.stringify({
      responseType: "summary",
      title: "Cancelled",
      summary: "Action cancelled.",
      data: {
        sections: [
          {
            heading: "",
            body: "No changes were made. Let me know if you'd like to do something else."
          }
        ],
        badges: []
      },
      actions: []
    });
    const historyEl = this.template.querySelector("c-lnchat-history");
    if (historyEl) historyEl.addMessage("assistant", cancelJson, "summary");
  }

  async handleAlertProceed() {
    if (!this._pendingBypassAction) return;
    const { operation, objectApiName, recordId, fields } =
      this._pendingBypassAction;
    this._pendingBypassAction = null;
    // Re-fire the confirm event with bypassDuplicate = true
    this.handleRecordActionConfirm({
      detail: {
        operation,
        objectApiName,
        recordId,
        fields,
        bypassDuplicate: true
      }
    });
  }

  handleAlertCancel() {
    this._pendingBypassAction = null;
    const cancelJson = JSON.stringify({
      responseType: "summary",
      title: "Cancelled",
      summary: "Action cancelled. No record was created.",
      data: { sections: [], badges: [] },
      actions: []
    });
    const historyEl = this.template.querySelector("c-lnchat-history");
    if (historyEl) historyEl.addMessage("assistant", cancelJson, "summary");
  }

  handleRecordNavigate(event) {
    const { recordId } = event.detail;
    if (!recordId) return;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        actionName: "view"
      }
    });
  }

  handleShowToast(event) {
    const { title, message, variant } = event.detail;
    this.dispatchEvent(
      new ShowToastEvent({ title, message, variant: variant || "info" })
    );
  }

  handleMinimize() {
    this.isMinimized = !this.isMinimized;

    this.dispatchEvent(
      new CustomEvent("utilitybarminimize", {
        bubbles: true,
        composed: true
      })
    );
  }
}
