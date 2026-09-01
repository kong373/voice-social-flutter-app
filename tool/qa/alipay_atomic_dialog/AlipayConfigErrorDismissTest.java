package com.kong373.voicesocial.qa;

import android.graphics.Rect;
import android.view.accessibility.AccessibilityNodeInfo;

import com.android.uiautomator.core.UiDevice;
import com.android.uiautomator.core.UiObject;
import com.android.uiautomator.core.UiObjectNotFoundException;
import com.android.uiautomator.core.UiSelector;
import com.android.uiautomator.testrunner.UiAutomatorTestCase;

import java.util.ArrayList;
import java.util.List;

/**
 * Device-side, fail-closed dismissal of one exact Alipay sandbox CONFIG_ERROR
 * dialog. The final click resolves the exact button selector only after a
 * bounded, allowlisted accessibility-ancestor check at action time, so no
 * host-side coordinates are ever used.
 */
public final class AlipayConfigErrorDismissTest extends UiAutomatorTestCase {
    private static final String TARGET_PACKAGE = "com.eg.android.AlipayGphoneRC";
    private static final String TARGET_ACTIVITY =
            "com.alipay.android.msp.ui.views.MspContainerActivity";
    private static final String ERROR_TEXT = "人气太旺啦，稍候再试试。(6)";
    private static final String BUTTON_TEXT = "确定";
    private static final String FOREIGN_PACKAGE_PATTERN =
            "^(?!com\\.eg\\.android\\.AlipayGphoneRC$).+$";
    private static final String PASS_MARKER =
            "ALIPAY_ATOMIC_DIALOG_PROBE::DISMISS_CLICKED";

    private static final String[] DANGEROUS_TEXT = {
        "支付", "付款", "充值", "密码", "验证码", "银行卡", "余额",
        "pay", "payment", "password", "passcode", "otp", "security code"
    };
    private static final int MAX_SHARED_ANCESTOR_DEPTH = 3;
    private static final String[] ALLOWED_CONTAINER_CLASSES = {
        "android.app.Dialog",
        "android.view.ViewGroup",
        "android.widget.ConstraintLayout",
        "android.widget.FrameLayout",
        "android.widget.LinearLayout",
        "android.widget.RelativeLayout",
        "android.widget.TableLayout",
        "android.widget.GridLayout",
        "android.widget.ScrollView"
    };

    private static final class Snapshot {
        final Rect bounds;
        final int rotation;

        Snapshot(Rect bounds, int rotation) {
            this.bounds = new Rect(bounds);
            this.rotation = rotation;
        }
    }

    private static final class InspectableUiObject extends UiObject {
        InspectableUiObject(UiSelector selector) {
            super(selector);
        }

        AccessibilityNodeInfo node() throws UiObjectNotFoundException {
            AccessibilityNodeInfo value = findAccessibilityNodeInfo(5000);
            if (value == null) {
                throw new UiObjectNotFoundException("accessibility node is unavailable");
            }
            return value;
        }
    }

    private static final class Ancestor {
        final AccessibilityNodeInfo node;
        final int depth;

        Ancestor(AccessibilityNodeInfo node, int depth) {
            this.node = node;
            this.depth = depth;
        }
    }

    private static UiSelector errorSelector() {
        return new UiSelector()
                .packageName(TARGET_PACKAGE)
                .className("android.widget.TextView")
                .text(ERROR_TEXT);
    }

    private static UiSelector buttonSelector() {
        return new UiSelector()
                .packageName(TARGET_PACKAGE)
                .className("android.widget.Button")
                .text(BUTTON_TEXT)
                .enabled(true)
                .clickable(true);
    }

    private static UiObject object(UiSelector selector) {
        return new UiObject(selector);
    }

    private static void requireExactlyOne(UiSelector first, UiSelector second, String message) {
        assertTrue(message, object(first).exists());
        assertFalse(message, object(second).exists());
    }

    private static void requireNoObject(UiSelector selector, String message) {
        assertFalse(message, object(selector).exists());
    }

    private static boolean allowedContainer(AccessibilityNodeInfo node) {
        CharSequence className = node.getClassName();
        if (className == null) {
            return false;
        }
        String value = className.toString();
        for (String allowed : ALLOWED_CONTAINER_CLASSES) {
            if (allowed.equals(value)) {
                return true;
            }
        }
        return false;
    }

    private static List<Ancestor> ancestors(AccessibilityNodeInfo node) {
        List<Ancestor> result = new ArrayList<Ancestor>();
        AccessibilityNodeInfo current = node.getParent();
        for (int depth = 1;
                current != null && depth <= MAX_SHARED_ANCESTOR_DEPTH;
                depth++) {
            result.add(new Ancestor(current, depth));
            current = current.getParent();
        }
        return result;
    }

    private static boolean sameAccessibilityNode(
            AccessibilityNodeInfo left, AccessibilityNodeInfo right) {
        return left != null && right != null && left.equals(right);
    }

    private static void requireBoundedAncestorRelation(
            UiObject error, UiObject button) throws UiObjectNotFoundException {
        AccessibilityNodeInfo errorNode = new InspectableUiObject(errorSelector().instance(0)).node();
        AccessibilityNodeInfo buttonNode = new InspectableUiObject(buttonSelector().instance(0)).node();
        List<Ancestor> errorAncestors = ancestors(errorNode);
        List<Ancestor> buttonAncestors = ancestors(buttonNode);
        Ancestor common = null;
        Ancestor buttonCommon = null;
        for (Ancestor errorAncestor : errorAncestors) {
            for (Ancestor buttonAncestor : buttonAncestors) {
                if (sameAccessibilityNode(errorAncestor.node, buttonAncestor.node)) {
                    common = errorAncestor;
                    buttonCommon = buttonAncestor;
                    break;
                }
            }
            if (common != null) {
                break;
            }
        }
        assertNotNull("error and dismiss Button have no bounded common ancestor", common);
        assertTrue("common ancestor depth is unsafe", common.depth <= MAX_SHARED_ANCESTOR_DEPTH);
        assertTrue("button common ancestor depth is unsafe",
                buttonCommon.depth <= MAX_SHARED_ANCESTOR_DEPTH);

        for (Ancestor ancestor : errorAncestors) {
            if (ancestor.depth > common.depth) {
                break;
            }
            assertEquals("ancestor package is not Alipay", TARGET_PACKAGE,
                    String.valueOf(ancestor.node.getPackageName()));
            assertTrue("ancestor class is not an allowlisted container",
                    allowedContainer(ancestor.node));
        }
        for (Ancestor ancestor : buttonAncestors) {
            if (ancestor.depth > buttonCommon.depth) {
                break;
            }
            assertEquals("ancestor package is not Alipay", TARGET_PACKAGE,
                    String.valueOf(ancestor.node.getPackageName()));
            assertTrue("ancestor class is not an allowlisted container",
                    allowedContainer(ancestor.node));
        }
    }

    private static boolean sameNode(UiObject left, UiObject right)
            throws UiObjectNotFoundException {
        return left.exists()
                && right.exists()
                && TARGET_PACKAGE.equals(left.getPackageName())
                && TARGET_PACKAGE.equals(right.getPackageName())
                && left.getClassName().equals(right.getClassName())
                && left.getText().equals(right.getText())
                && left.getVisibleBounds().equals(right.getVisibleBounds());
    }

    private static UiObject verifyAndResolveButton(UiDevice device)
            throws UiObjectNotFoundException {
        assertEquals("wrong foreground package", TARGET_PACKAGE,
                device.getCurrentPackageName());
        assertEquals("wrong foreground activity", TARGET_ACTIVITY,
                device.getCurrentActivityName());

        requireExactlyOne(
                errorSelector().instance(0),
                errorSelector().instance(1),
                "exact error TextView must be unique");
        requireExactlyOne(
                buttonSelector().instance(0),
                buttonSelector().instance(1),
                "exact dismiss Button must be unique");
        requireExactlyOne(
                new UiSelector().packageName(TARGET_PACKAGE)
                        .className("android.widget.Button").instance(0),
                new UiSelector().packageName(TARGET_PACKAGE)
                        .className("android.widget.Button").instance(1),
                "all Buttons must be unique");
        requireExactlyOne(
                new UiSelector().clickable(true).instance(0),
                new UiSelector().clickable(true).instance(1),
                "the complete active UI must expose one clickable node");

        requireNoObject(
                new UiSelector().packageNameMatches(FOREIGN_PACKAGE_PATTERN),
                "foreign-package overlay or UI node is forbidden");

        requireNoObject(
                new UiSelector()
                        .classNameMatches(".*(WebView|EditText|AutoCompleteTextView).*$"),
                "input or WebView surface is forbidden");
        requireNoObject(
                new UiSelector().longClickable(true),
                "long-clickable surface is forbidden");
        requireNoObject(
                new UiSelector().scrollable(true),
                "scrollable surface is forbidden");
        requireNoObject(
                new UiSelector().checkable(true),
                "checkable surface is forbidden");
        for (String phrase : DANGEROUS_TEXT) {
            requireNoObject(
                    new UiSelector().textContains(phrase),
                    "dangerous visible text is forbidden");
            requireNoObject(
                    new UiSelector().descriptionContains(phrase),
                    "dangerous content description is forbidden");
        }

        UiObject error = object(errorSelector().instance(0));
        UiObject globalButton = object(buttonSelector().instance(0));
        UiObject onlyClickable = object(new UiSelector().clickable(true).instance(0));
        assertTrue("global Button differs from the only clickable node",
                sameNode(globalButton, onlyClickable));
        requireBoundedAncestorRelation(error, globalButton);
        assertTrue("dismiss Button is disabled", globalButton.isEnabled());
        assertTrue("dismiss Button is not clickable", globalButton.isClickable());

        int width = device.getDisplayWidth();
        int height = device.getDisplayHeight();
        assertTrue("invalid display bounds", width > 0 && height > 0);
        Rect errorBounds = error.getVisibleBounds();
        assertTrue("error TextView is hidden or has empty bounds",
                errorBounds.width() > 1 && errorBounds.height() > 1);
        assertTrue("error TextView leaves the display",
                errorBounds.left >= 0 && errorBounds.top >= 0
                        && errorBounds.right <= width && errorBounds.bottom <= height);
        Rect bounds = globalButton.getVisibleBounds();
        assertTrue("dismiss bounds are empty", bounds.width() > 1 && bounds.height() > 1);
        assertTrue("dismiss bounds leave the display",
                bounds.left >= 0 && bounds.top >= 0
                        && bounds.right <= width && bounds.bottom <= height);
        assertTrue("dismiss surface is too large",
                ((long) bounds.width()) * bounds.height() <= ((long) width) * height * 40 / 100);
        return globalButton;
    }

    public void testDismissConfigError() throws Exception {
        UiDevice device = getUiDevice();
        device.setCompressedLayoutHeirarchy(false);
        device.waitForIdle(1000);
        UiObject firstButton = verifyAndResolveButton(device);
        Snapshot first = new Snapshot(firstButton.getVisibleBounds(), device.getDisplayRotation());

        sleep(120);
        device.waitForIdle(1000);
        UiObject secondButton = verifyAndResolveButton(device);
        Snapshot second = new Snapshot(secondButton.getVisibleBounds(), device.getDisplayRotation());
        assertEquals("dialog bounds changed before action", first.bounds, second.bounds);
        assertEquals("display rotation changed before action", first.rotation, second.rotation);

        // Resolve the relation a final time immediately before the action. A
        // page transition invalidates the bounded ancestor relation and fails
        // closed instead of reusing host coordinates.
        UiObject actionButton = verifyAndResolveButton(device);
        assertEquals("dialog bounds changed at action time",
                second.bounds, actionButton.getVisibleBounds());
        assertEquals("display rotation changed at action time",
                second.rotation, device.getDisplayRotation());
        assertTrue("atomic dismiss action failed", actionButton.click());
        System.out.println(PASS_MARKER);
    }
}
