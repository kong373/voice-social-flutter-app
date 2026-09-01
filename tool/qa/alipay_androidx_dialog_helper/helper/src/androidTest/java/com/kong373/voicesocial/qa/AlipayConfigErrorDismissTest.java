package com.kong373.voicesocial.qa;

import android.app.Instrumentation;
import android.graphics.Rect;
import android.os.Bundle;
import android.view.accessibility.AccessibilityNodeInfo;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;

import org.junit.Assert;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

/**
 * Standalone AndroidX instrumentation for one exact Alipay sandbox error
 * dialog. The base APK is intentionally empty and this test never starts,
 * stops, or instruments the Flutter app or the Alipay wallet. The final
 * dismiss test performs one UiAutomator object click only after it has
 * revalidated the complete accessibility relation on the device.
 */
@RunWith(AndroidJUnit4.class)
public final class AlipayConfigErrorDismissTest {
    private static final String TARGET_PACKAGE = "com.eg.android.AlipayGphoneRC";
    private static final String TARGET_ACTIVITY =
            "com.alipay.android.msp.ui.views.MspContainerActivity";
    private static final String SYSTEM_UI_PACKAGE = "com.android.systemui";
    private static final String ERROR_TEXT = "人气太旺啦，稍候再试试。(6)";
    private static final String BUTTON_TEXT = "确定";
    private static final String PASS_MARKER =
            "ALIPAY_ATOMIC_DIALOG_PROBE::DISMISS_CLICKED";
    private static final String VERIFY_PASS_MARKER =
            "ALIPAY_ATOMIC_DIALOG_PROBE::VERIFY_PASSED";
    private static final int MAX_SHARED_ANCESTOR_DEPTH = 3;
    private static final int STABILITY_DELAY_MILLIS = 120;

    private static final Pattern UNSAFE_CLASS_PATTERN = Pattern.compile(
            ".*(WebView|EditText|AutoCompleteTextView|Input).*");
    private static final Pattern NON_PLATFORM_CLASS_PATTERN = Pattern.compile(
            "^(?!android\\.|androidx\\.).+");
    private static final String[] DANGEROUS_TEXT = {
        "支付", "付款", "充值", "密码", "验证码", "银行卡", "余额",
        "pay", "payment", "password", "passcode", "otp", "security code"
    };
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
    private static final Pattern AUTHORITY_FIELD_PATTERN = Pattern.compile(
            "(^|\\s)(mResumedActivity|ResumedActivity|topResumedActivity|"
                    + "mFocusedApp|mCurrentFocus|mFocusedWindow|mTopActivity|"
                    + "topActivity)(:|=)");
    private static final Pattern COMPONENT_PATTERN = Pattern.compile(
            "[A-Za-z0-9_.$-]+/[A-Za-z0-9_.$-]+");

    private static final class Snapshot {
        final Rect buttonBounds;
        final int rotation;
        final String buttonText;

        Snapshot(Rect buttonBounds, int rotation, String buttonText) {
            this.buttonBounds = new Rect(buttonBounds);
            this.rotation = rotation;
            this.buttonText = buttonText;
        }
    }

    private static UiDevice device() {
        return UiDevice.getInstance(
                InstrumentationRegistry.getInstrumentation());
    }

    private static void emitStatusMarker(String marker) {
        Bundle status = new Bundle();
        status.putString(Instrumentation.REPORT_KEY_STREAMRESULT, marker);
        InstrumentationRegistry.getInstrumentation().sendStatus(0, status);
    }

    private static boolean isAllowedContainer(UiObject2 node) {
        String className = node.getClassName();
        if (className == null) {
            return false;
        }
        for (String allowed : ALLOWED_CONTAINER_CLASSES) {
            if (allowed.equals(className)) {
                return true;
            }
        }
        return false;
    }

    private static List<UiObject2> ancestors(UiObject2 node) {
        List<UiObject2> result = new ArrayList<>();
        UiObject2 current = node.getParent();
        for (int depth = 1;
                current != null && depth <= MAX_SHARED_ANCESTOR_DEPTH;
                depth++) {
            result.add(current);
            current = current.getParent();
        }
        return result;
    }

    private static boolean sameNode(UiObject2 left, UiObject2 right) {
        if (left == null || right == null) {
            return false;
        }
        return String.valueOf(left.getApplicationPackage()).equals(
                    String.valueOf(right.getApplicationPackage()))
                && String.valueOf(left.getClassName()).equals(
                    String.valueOf(right.getClassName()))
                && String.valueOf(left.getText()).equals(
                    String.valueOf(right.getText()))
                && String.valueOf(left.getContentDescription()).equals(
                    String.valueOf(right.getContentDescription()))
                && left.getVisibleBounds().equals(right.getVisibleBounds());
    }

    private static String normalizeComponent(String value) {
        int slash = value.indexOf('/');
        if (slash < 1 || slash == value.length() - 1) {
            return value;
        }
        String packageName = value.substring(0, slash);
        String activityName = value.substring(slash + 1);
        if (activityName.startsWith(".")) {
            activityName = packageName + activityName;
        }
        return packageName + "/" + activityName;
    }

    /**
     * UiDevice's current-package accessor is the package that most recently
     * emitted an accessibility event, not a foreground authority signal. Use
     * a device-side dumpsys query and accept only exact authority fields for
     * the known Alipay sandbox component. The output is inspected in memory
     * and never printed or returned as test evidence.
     */
    private static void requireTargetForeground(UiDevice uiDevice)
            throws IOException {
        String dump = uiDevice.executeShellCommand(
                "dumpsys activity activities");
        boolean targetFound = false;
        for (String line : dump.split("\\R")) {
            if (!AUTHORITY_FIELD_PATTERN.matcher(line).find()) {
                continue;
            }
            java.util.regex.Matcher matcher = COMPONENT_PATTERN.matcher(line);
            boolean lineHasComponent = false;
            while (matcher.find()) {
                lineHasComponent = true;
                String normalized = normalizeComponent(matcher.group());
                if ((TARGET_PACKAGE + "/" + TARGET_ACTIVITY).equals(normalized)) {
                    targetFound = true;
                } else {
                    Assert.fail("foreground activity authority is not Alipay");
                }
            }
            Assert.assertTrue("foreground activity authority is incomplete",
                    lineHasComponent);
        }
        Assert.assertTrue("exact Alipay foreground activity was not observed",
                targetFound);
    }

    private static void requireBoundedAncestorRelation(
            UiObject2 error, UiObject2 button) {
        List<UiObject2> errorAncestors = ancestors(error);
        List<UiObject2> buttonAncestors = ancestors(button);
        UiObject2 common = null;
        int errorDepth = 0;
        int buttonDepth = 0;
        for (int left = 0; left < errorAncestors.size(); left++) {
            for (int right = 0; right < buttonAncestors.size(); right++) {
                if (sameNode(errorAncestors.get(left), buttonAncestors.get(right))) {
                    common = errorAncestors.get(left);
                    errorDepth = left + 1;
                    buttonDepth = right + 1;
                    break;
                }
            }
            if (common != null) {
                break;
            }
        }
        Assert.assertNotNull(
                "error and dismiss Button have no bounded common ancestor", common);
        Assert.assertTrue("common ancestor depth is unsafe",
                errorDepth <= MAX_SHARED_ANCESTOR_DEPTH);
        Assert.assertTrue("button common ancestor depth is unsafe",
                buttonDepth <= MAX_SHARED_ANCESTOR_DEPTH);
        for (int index = 0; index < errorDepth; index++) {
            UiObject2 ancestor = errorAncestors.get(index);
            Assert.assertEquals("ancestor package is not Alipay",
                    TARGET_PACKAGE, ancestor.getApplicationPackage());
            Assert.assertTrue("ancestor class is not allowlisted",
                    isAllowedContainer(ancestor));
        }
        for (int index = 0; index < buttonDepth; index++) {
            UiObject2 ancestor = buttonAncestors.get(index);
            Assert.assertEquals("ancestor package is not Alipay",
                    TARGET_PACKAGE, ancestor.getApplicationPackage());
            Assert.assertTrue("ancestor class is not allowlisted",
                    isAllowedContainer(ancestor));
        }
    }

    private static void requireExactlyOne(List<UiObject2> nodes, String message) {
        Assert.assertEquals(message, 1, nodes.size());
    }

    private static void rejectForeignWindowRoots(UiDevice uiDevice) {
        int targetRootCount = 0;
        int width = uiDevice.getDisplayWidth();
        int height = uiDevice.getDisplayHeight();
        Assert.assertTrue("invalid display bounds", width > 0 && height > 0);
        for (AccessibilityNodeInfo root : uiDevice.getWindowRoots()) {
            String packageName = String.valueOf(root.getPackageName());
            if (TARGET_PACKAGE.equals(packageName)) {
                targetRootCount++;
                continue;
            }
            Assert.assertEquals("foreign window root is forbidden",
                    SYSTEM_UI_PACKAGE, packageName);
            Assert.assertTrue("system UI root class is unsafe",
                    String.valueOf(root.getClassName()).startsWith("android."));
            Assert.assertFalse("system UI root is clickable", root.isClickable());
            Assert.assertFalse("system UI root is long-clickable", root.isLongClickable());
            Assert.assertFalse("system UI root is scrollable", root.isScrollable());
            Assert.assertFalse("system UI root is checkable", root.isCheckable());
            Rect bounds = new Rect();
            root.getBoundsInScreen(bounds);
            Assert.assertTrue("system UI root bounds are empty",
                    bounds.width() > 0 && bounds.height() > 0);
            Assert.assertTrue("system UI root leaves display",
                    bounds.left >= 0 && bounds.top >= 0
                            && bounds.right <= width && bounds.bottom <= height);
            Assert.assertTrue("system UI surface is too large",
                    ((long) bounds.width()) * bounds.height()
                            <= ((long) width) * height * 20 / 100);
        }
        Assert.assertEquals("exact Alipay window root must be unique",
                1, targetRootCount);
    }

    private static void rejectUnsafeSurface(UiDevice uiDevice) {
        rejectForeignWindowRoots(uiDevice);
        Assert.assertTrue("input or WebView surface is forbidden",
                uiDevice.findObjects(By.pkg(TARGET_PACKAGE)
                        .clazz(UNSAFE_CLASS_PATTERN)).isEmpty());
        Assert.assertTrue("non-platform UI class is forbidden",
                uiDevice.findObjects(By.pkg(TARGET_PACKAGE)
                        .clazz(NON_PLATFORM_CLASS_PATTERN)).isEmpty());
        Assert.assertTrue("long-clickable surface is forbidden",
                uiDevice.findObjects(By.pkg(TARGET_PACKAGE)
                        .longClickable(true)).isEmpty());
        Assert.assertTrue("scrollable surface is forbidden",
                uiDevice.findObjects(By.pkg(TARGET_PACKAGE)
                        .scrollable(true)).isEmpty());
        Assert.assertTrue("checkable surface is forbidden",
                uiDevice.findObjects(By.pkg(TARGET_PACKAGE)
                        .checkable(true)).isEmpty());
        for (String phrase : DANGEROUS_TEXT) {
            Assert.assertTrue("dangerous visible text is forbidden: " + phrase,
                    uiDevice.findObjects(By.pkg(TARGET_PACKAGE)
                            .textContains(phrase)).isEmpty());
            Assert.assertTrue("dangerous content description is forbidden: " + phrase,
                    uiDevice.findObjects(By.pkg(TARGET_PACKAGE)
                            .descContains(phrase)).isEmpty());
        }
    }

    private static UiObject2 verifyAndResolveButton(UiDevice uiDevice)
            throws IOException {
        requireTargetForeground(uiDevice);

        List<UiObject2> errors = uiDevice.findObjects(
                By.pkg(TARGET_PACKAGE).clazz("android.widget.TextView")
                        .text(ERROR_TEXT));
        requireExactlyOne(errors, "exact error TextView must be unique");
        List<UiObject2> buttons = uiDevice.findObjects(
                By.pkg(TARGET_PACKAGE).clazz("android.widget.Button")
                        .text(BUTTON_TEXT).enabled(true).clickable(true));
        requireExactlyOne(buttons, "exact dismiss Button must be unique");
        List<UiObject2> allButtons = uiDevice.findObjects(
                By.pkg(TARGET_PACKAGE).clazz("android.widget.Button"));
        requireExactlyOne(allButtons, "all Buttons must be unique");
        List<UiObject2> clickable = uiDevice.findObjects(
                By.pkg(TARGET_PACKAGE).clickable(true));
        requireExactlyOne(clickable, "the complete active UI must expose one clickable node");
        Assert.assertTrue("global clickable node differs from dismiss Button",
                sameNode(buttons.get(0), clickable.get(0)));
        rejectUnsafeSurface(uiDevice);
        requireBoundedAncestorRelation(errors.get(0), buttons.get(0));

        UiObject2 button = buttons.get(0);
        Assert.assertTrue("dismiss Button is disabled", button.isEnabled());
        Assert.assertTrue("dismiss Button is not clickable", button.isClickable());
        int width = uiDevice.getDisplayWidth();
        int height = uiDevice.getDisplayHeight();
        Assert.assertTrue("invalid display bounds", width > 0 && height > 0);
        Rect errorBounds = errors.get(0).getVisibleBounds();
        Assert.assertTrue("error TextView is hidden or has empty bounds",
                errorBounds.width() > 1 && errorBounds.height() > 1);
        Assert.assertTrue("error TextView leaves display",
                errorBounds.left >= 0 && errorBounds.top >= 0
                        && errorBounds.right <= width && errorBounds.bottom <= height);
        Rect buttonBounds = button.getVisibleBounds();
        Assert.assertTrue("dismiss bounds are empty",
                buttonBounds.width() > 1 && buttonBounds.height() > 1);
        Assert.assertTrue("dismiss bounds leave display",
                buttonBounds.left >= 0 && buttonBounds.top >= 0
                        && buttonBounds.right <= width && buttonBounds.bottom <= height);
        Assert.assertTrue("dismiss surface is too large",
                ((long) buttonBounds.width()) * buttonBounds.height()
                        <= ((long) width) * height * 40 / 100);
        return button;
    }

    private static Snapshot snapshot(UiDevice uiDevice) throws IOException {
        UiObject2 button = verifyAndResolveButton(uiDevice);
        return new Snapshot(button.getVisibleBounds(),
                uiDevice.getDisplayRotation(), button.getText());
    }

    @Test
    public void testVerifyConfigError() throws IOException {
        UiDevice uiDevice = device();
        uiDevice.waitForIdle(1000);
        verifyAndResolveButton(uiDevice);
        emitStatusMarker(VERIFY_PASS_MARKER);
    }

    @Test
    public void testDismissConfigError() throws Exception {
        UiDevice uiDevice = device();
        uiDevice.waitForIdle(1000);
        Snapshot first = snapshot(uiDevice);
        Thread.sleep(STABILITY_DELAY_MILLIS);
        uiDevice.waitForIdle(1000);
        Snapshot second = snapshot(uiDevice);
        Assert.assertEquals("dialog bounds changed before action",
                first.buttonBounds, second.buttonBounds);
        Assert.assertEquals("display rotation changed before action",
                first.rotation, second.rotation);
        Assert.assertEquals("button text changed before action",
                first.buttonText, second.buttonText);

        // This is the final device-side verification. There is no wait, query,
        // or other UiAutomator operation after the click.
        UiObject2 actionButton = verifyAndResolveButton(uiDevice);
        Assert.assertEquals("dialog bounds changed at action time",
                second.buttonBounds, actionButton.getVisibleBounds());
        Assert.assertEquals("display rotation changed at action time",
                second.rotation, uiDevice.getDisplayRotation());
        actionButton.click();
        emitStatusMarker(PASS_MARKER);
    }
}
